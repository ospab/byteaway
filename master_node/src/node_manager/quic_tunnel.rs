use super::registry::{ConnectionType, NodeMetadata, NodeRegistry, WsCommand};
use anyhow::{anyhow, Context};
use quinn::{Connection, Endpoint, RecvStream, SendStream, ServerConfig};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::mpsc;
use tracing::{info, warn};
use uuid::Uuid;

pub struct QuicTunnelState {
    pub registry: Arc<dyn NodeRegistry>,
    pub app_state: Arc<crate::state::AppState>,
}

#[derive(Debug, Deserialize, Serialize)]
struct QuicHello {
    device_id: String,
    token: String,
    country: String,
    conn_type: String,
    speed_mbps: Option<u32>,
}

mod wire {
    use uuid::Uuid;

    pub const CMD_CONNECT: u8 = 0x01;
    pub const CMD_DATA: u8 = 0x02;
    pub const CMD_CLOSE: u8 = 0x03;

    pub fn encode(cmd: u8, session_id: Uuid, payload: &[u8]) -> Vec<u8> {
        let mut frame = Vec::with_capacity(1 + 16 + payload.len());
        frame.push(cmd);
        frame.extend_from_slice(session_id.as_bytes());
        frame.extend_from_slice(payload);
        frame
    }

    pub fn decode(data: &[u8]) -> Option<(u8, Uuid, &[u8])> {
        if data.len() < 17 {
            return None;
        }
        let cmd = data[0];
        let sid = Uuid::from_bytes(data[1..17].try_into().ok()?);
        Some((cmd, sid, &data[17..]))
    }
}

pub async fn run_quic_server(
    bind_addr: SocketAddr,
    cert_path: &str,
    key_path: &str,
    state: Arc<QuicTunnelState>,
) -> anyhow::Result<()> {
    let server_config = load_server_config(cert_path, key_path)?;
    let endpoint = Endpoint::server(server_config, bind_addr)
        .with_context(|| format!("failed to bind QUIC listener on {}", bind_addr))?;

    info!("QUIC node ingress listening on {}", bind_addr);

    while let Some(incoming) = endpoint.accept().await {
        let state_cloned = state.clone();
        tokio::spawn(async move {
            match incoming.await {
                Ok(conn) => {
                    if let Err(e) = handle_connection(conn, state_cloned).await {
                        warn!("QUIC connection ended with error: {e}");
                    }
                }
                Err(e) => warn!("QUIC handshake failed: {e}"),
            }
        });
    }

    Ok(())
}

async fn handle_connection(conn: Connection, state: Arc<QuicTunnelState>) -> anyhow::Result<()> {
    let remote = conn.remote_address();
    let (mut send, mut recv) = conn
        .accept_bi()
        .await
        .context("client didn't open control stream")?;

    let hello_frame = read_len_prefixed(&mut recv)
        .await
        .context("failed to read hello frame")?
        .ok_or_else(|| anyhow!("empty hello frame"))?;

    let hello: QuicHello = serde_json::from_slice(&hello_frame)
        .context("invalid hello json")?;

    let (node_uuid, meta) = authenticate_and_build_meta(&state, &hello, remote).await?;

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<WsCommand>(1024);
    state
        .registry
        .register_node(meta.clone(), cmd_tx)
        .await
        .context("failed to register node")?;

    info!("QUIC node connected: {} country={} remote={}", node_uuid, meta.country, remote);

    let mut sessions: HashMap<Uuid, mpsc::Sender<Vec<u8>>> = HashMap::new();
    let mut heartbeat_interval = tokio::time::interval(std::time::Duration::from_secs(30));
    let frame_read_error_logged = Arc::new(AtomicBool::new(false));

    // Dedicated reader task prevents cancellation of partial reads in select! loops.
    let (frame_tx, mut frame_rx) = mpsc::channel::<Vec<u8>>(1024);
    let frame_read_error_logged_reader = frame_read_error_logged.clone();
    let node_uuid_reader = node_uuid;
    let reader_task = tokio::spawn(async move {
        loop {
            match read_len_prefixed(&mut recv).await {
                Ok(Some(data)) => {
                    if frame_tx.send(data).await.is_err() {
                        break;
                    }
                }
                Ok(None) => break,
                Err(e) => {
                    if !frame_read_error_logged_reader.swap(true, Ordering::Relaxed) {
                        warn!("QUIC read_len_prefixed failed for node {}: {}", node_uuid_reader, e);
                    }
                    break;
                }
            }
        }
    });

    loop {
        tokio::select! {
            _ = heartbeat_interval.tick() => {
                if let Err(e) = state.registry.heartbeat(node_uuid).await {
                    warn!("QUIC heartbeat failed for node {}: {:?}", node_uuid, e);
                    break;
                }
            }

            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(WsCommand::Open { session_id, target_addr, reply_tx }) => {
                        info!("QUIC OPEN -> node={} sid={} target={}", node_uuid, session_id, target_addr);
                        let frame = wire::encode(wire::CMD_CONNECT, session_id, target_addr.as_bytes());
                        if write_len_prefixed(&mut send, &frame).await.is_err() {
                            break;
                        }
                        sessions.insert(session_id, reply_tx);
                    }
                    Some(WsCommand::Data { session_id, payload }) => {
                        if payload.len() >= 16 * 1024 {
                            info!("QUIC DATA -> node={} sid={} bytes={}", node_uuid, session_id, payload.len());
                        }
                        let frame = wire::encode(wire::CMD_DATA, session_id, &payload);
                        if write_len_prefixed(&mut send, &frame).await.is_err() {
                            break;
                        }
                    }
                    Some(WsCommand::Close { session_id }) => {
                        info!("QUIC CLOSE -> node={} sid={}", node_uuid, session_id);
                        let frame = wire::encode(wire::CMD_CLOSE, session_id, &[]);
                        let _ = write_len_prefixed(&mut send, &frame).await;
                        sessions.remove(&session_id);
                    }
                    None => break,
                }
            }

            frame = frame_rx.recv() => {
                match frame {
                    Some(data) => {
                        if let Some((cmd, sid, payload)) = wire::decode(&data) {
                            match cmd {
                                wire::CMD_DATA => {
                                    if payload.len() >= 16 * 1024 {
                                        info!("QUIC DATA <- node={} sid={} bytes={}", node_uuid, sid, payload.len());
                                    }
                                    if let Some(tx) = sessions.get(&sid) {
                                        let tx = tx.clone();
                                        let payload = payload.to_vec();
                                        tokio::spawn(async move {
                                            if tx.send(payload).await.is_err() {
                                                // Removal is handled by CMD_CLOSE or next loop.
                                            }
                                        });
                                    } else {
                                        warn!("QUIC DATA for unknown session: node={} sid={} bytes={}", node_uuid, sid, payload.len());
                                    }
                                }
                                wire::CMD_CLOSE => {
                                    info!("QUIC CLOSE <- node={} sid={}", node_uuid, sid);
                                    sessions.remove(&sid);
                                }
                                _ => {}
                            }
                        }
                    }
                    None => {
                        if frame_read_error_logged.load(Ordering::Relaxed) {
                            warn!("QUIC frame stream ended after read error for node {}", node_uuid);
                        } else {
                            warn!("QUIC frame stream ended cleanly for node {}", node_uuid);
                        }
                        break;
                    }
                }
            }
        }
    }

    let _ = state.registry.remove_node(node_uuid, &meta.country).await;
    info!("QUIC node disconnected: {} country={}", node_uuid, meta.country);
    reader_task.abort();
    let _ = send.finish();
    Ok(())
}

async fn authenticate_and_build_meta(
    state: &Arc<QuicTunnelState>,
    hello: &QuicHello,
    remote: SocketAddr,
) -> anyhow::Result<(Uuid, NodeMetadata)> {
    let safe_device_id = hello.device_id.trim();

    let auth_ctx = state
        .app_state
        .authenticator
        .authenticate(&hello.token, &remote.ip().to_string())
        .await
        .map_err(|_| {
            warn!(
                "QUIC auth failed: remote={} country={} conn_type={} device_id_len={}",
                remote,
                hello.country,
                hello.conn_type,
                safe_device_id.len()
            );
            anyhow!("auth failed")
        })?;

    let owner_by_device: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM mobile_nodes WHERE device_id = $1"
    )
    .bind(safe_device_id)
    .fetch_optional(&state.app_state.db_pool)
    .await
    .context("device lookup failed")?;

    let owner_node_id = match owner_by_device {
        Some(v) => v,
        None => {
            // Self-heal: if token owner exists as mobile node, rebind current device_id.
            let token_owner_exists: Option<Uuid> = sqlx::query_scalar(
                "SELECT id FROM mobile_nodes WHERE id = $1"
            )
            .bind(auth_ctx.client_id)
            .fetch_optional(&state.app_state.db_pool)
            .await
            .context("token owner lookup failed")?;

            if let Some(node_id) = token_owner_exists {
                sqlx::query("UPDATE mobile_nodes SET device_id = $1, registered_at = NOW() WHERE id = $2")
                    .bind(safe_device_id)
                    .bind(node_id)
                    .execute(&state.app_state.db_pool)
                    .await
                    .context("device mapping self-heal failed")?;

                info!(
                    "QUIC auth self-healed device mapping: node_id={} new_device_id_len={} remote={}",
                    node_id,
                    safe_device_id.len(),
                    remote
                );
                node_id
            } else {
                warn!(
                    "QUIC auth reject: unknown device_id remote={} country={} conn_type={} device_id_len={}",
                    remote,
                    hello.country,
                    hello.conn_type,
                    safe_device_id.len()
                );
                return Err(anyhow!("unknown device_id"));
            }
        }
    };

    if auth_ctx.client_id != owner_node_id {
        warn!(
            "QUIC auth reject: token owner mismatch remote={} token_client_id={} owner_node_id={} country={} conn_type={}",
            remote,
            auth_ctx.client_id,
            owner_node_id,
            hello.country,
            hello.conn_type
        );
        return Err(anyhow!("token owner mismatch"));
    }

    let ct = if hello.conn_type.eq_ignore_ascii_case("wifi") {
        ConnectionType::WiFi
    } else {
        ConnectionType::Mobile
    };

    let meta = NodeMetadata {
        node_id: owner_node_id,
        ip_address: remote.ip(),
        country: hello.country.clone(),
        connection_type: ct,
        speed_mbps: hello.speed_mbps.unwrap_or(50),
    };

    Ok((owner_node_id, meta))
}

fn load_server_config(cert_path: &str, key_path: &str) -> anyhow::Result<ServerConfig> {
    let cert_path = Path::new(cert_path);
    let key_path = Path::new(key_path);

    let cert_file = std::fs::read(cert_path)
        .with_context(|| format!("failed to read cert: {}", cert_path.display()))?;
    let key_file = std::fs::read(key_path)
        .with_context(|| format!("failed to read key: {}", key_path.display()))?;

    let certs = rustls_pemfile::certs(&mut &cert_file[..])
        .collect::<Result<Vec<_>, _>>()
        .context("failed to parse cert chain")?;
    let key = rustls_pemfile::private_key(&mut &key_file[..])
        .context("failed to parse private key")?
        .ok_or_else(|| anyhow!("no private key found"))?;

    let mut cfg = ServerConfig::with_single_cert(certs, key)
        .context("invalid cert/key pair for QUIC")?;
    let transport = Arc::get_mut(&mut cfg.transport).ok_or_else(|| anyhow!("transport config unavailable"))?;
    transport.max_idle_timeout(Some(std::time::Duration::from_secs(300).try_into().unwrap()));
    transport.keep_alive_interval(Some(std::time::Duration::from_secs(3)));
    
    // Increase receive windows to prevent deadlock on large read_exact calls
    let window_size: u32 = 1048576 * 8; // 8 MB
    transport.stream_receive_window(window_size.into());
    transport.receive_window((window_size * 4).into());

    Ok(cfg)
}

async fn read_len_prefixed(recv: &mut RecvStream) -> anyhow::Result<Option<Vec<u8>>> {
    let len = match recv.read_u32().await {
        Ok(v) => v as usize,
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(anyhow!(e)),
    };
    if len == 0 || len > 4 * 1024 * 1024 {
        return Err(anyhow!("invalid frame length: {len}"));
    }
    let mut buf = vec![0u8; len];
    recv.read_exact(&mut buf).await?;
    Ok(Some(buf))
}

async fn write_len_prefixed(send: &mut SendStream, payload: &[u8]) -> anyhow::Result<()> {
    send.write_u32(payload.len() as u32).await?;
    send.write_all(payload).await?;
    send.flush().await?;
    Ok(())
}
