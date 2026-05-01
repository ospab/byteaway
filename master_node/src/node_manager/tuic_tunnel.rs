use super::registry::{ConnectionType, NodeMetadata, NodeRegistry, WsCommand};
use anyhow::{anyhow, Context};
use dashmap::DashMap;
use quinn::{Connection, Endpoint, RecvStream, SendStream, ServerConfig};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::mpsc;
use tracing::{info, warn, debug};
use uuid::Uuid;

#[allow(dead_code)]
pub struct TuicTunnelState {
    pub registry: Arc<dyn NodeRegistry>,
    pub app_state: Arc<crate::state::AppState>,
}

#[derive(Debug, Deserialize, Serialize)]
#[allow(dead_code)]
struct TuicHello {
    device_id: String,
    token: String,
    country: String,
    conn_type: String,
    speed_mbps: Option<u32>,
}

#[allow(dead_code)]
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


#[allow(dead_code)]
async fn handle_connection(conn: Connection, state: Arc<TuicTunnelState>) -> anyhow::Result<()> {
    let remote = conn.remote_address();
    let (mut send, mut recv) = conn
        .accept_bi()
        .await
        .context("client didn't open control stream")?;

    let hello_frame = read_len_prefixed(&mut recv)
        .await
        .context("failed to read hello frame")?
        .ok_or_else(|| anyhow!("empty hello frame"))?;

    let hello: TuicHello = serde_json::from_slice(&hello_frame)
        .context("invalid hello json")?;

    let (node_uuid, meta) = authenticate_and_build_meta(&state, &hello, remote).await?;

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<WsCommand>(1024);
    state
        .registry
        .register_node(meta.clone(), cmd_tx)
        .await
        .context("failed to register node")?;

    info!("TUIC node connected: {} country={} remote={}", node_uuid, meta.country, remote);

    let sessions = Arc::new(DashMap::<Uuid, mpsc::Sender<Vec<u8>>>::new());

    let sessions_reader = sessions.clone();
    let reader_task = tokio::spawn(async move {
        loop {
            match read_len_prefixed(&mut recv).await {
                Ok(Some(data)) => {
                    if let Some((cmd, sid, payload)) = wire::decode(&data) {
                        match cmd {
                            wire::CMD_DATA => {
                                if let Some(tx) = sessions_reader.get(&sid) {
                                    if let Err(e) = tx.try_send(payload.to_vec()) {
                                        warn!("[{}] Tunnel -> Router: SEND FAILED (buffer full or closed): {}", &sid.to_string()[..8], e);
                                    } else {
                                        debug!("[{}] Tunnel -> Router: {} bytes", &sid.to_string()[..8], payload.len());
                                    }
                                }
                            }
                            wire::CMD_CLOSE => {
                                sessions_reader.remove(&sid);
                            }
                            _ => {}
                        }
                    }
                }
                Ok(None) => break,
                Err(_) => break,
            }
        }
    });

    let sessions_writer = sessions.clone();
    let registry_writer = state.registry.clone();
    let mut heartbeat_interval = tokio::time::interval(std::time::Duration::from_secs(30));
    
    let writer_task = tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = heartbeat_interval.tick() => {
                    if let Err(_) = registry_writer.heartbeat(node_uuid).await {
                        break;
                    }
                }

                cmd = cmd_rx.recv() => {
                    match cmd {
                        Some(WsCommand::Open { session_id, target_addr, reply_tx }) => {
                            let (session_tx, mut session_rx) = mpsc::channel::<Vec<u8>>(1024);
                            tokio::spawn(async move {
                                while let Some(payload) = session_rx.recv().await {
                                    if reply_tx.send(payload).await.is_err() {
                                        break;
                                    }
                                }
                            });
                            sessions_writer.insert(session_id, session_tx);

                            let frame = wire::encode(wire::CMD_CONNECT, session_id, target_addr.as_bytes());
                            if write_len_prefixed(&mut send, &frame).await.is_err() { break; }
                        }
                        Some(WsCommand::Data { session_id, payload }) => {
                            let frame = wire::encode(wire::CMD_DATA, session_id, &payload);
                            if write_len_prefixed(&mut send, &frame).await.is_err() { break; }
                        }
                        Some(WsCommand::Close { session_id }) => {
                            let frame = wire::encode(wire::CMD_CLOSE, session_id, &[]);
                            let _ = write_len_prefixed(&mut send, &frame).await;
                            sessions_writer.remove(&session_id);
                        }
                        None => break,
                    }
                }
            }
        }
        let _ = send.finish();
    });

    tokio::select! {
        _ = reader_task => {},
        _ = writer_task => {},
    }

    let _ = state.registry.remove_node(node_uuid, &meta.country).await;
    info!("TUIC node disconnected: {} country={}", node_uuid, meta.country);
    
    Ok(())
}

#[allow(dead_code)]
async fn authenticate_and_build_meta(
    state: &Arc<TuicTunnelState>,
    hello: &TuicHello,
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
                "TUIC auth failed: remote={} country={} device_id={}",
                remote,
                hello.country,
                safe_device_id
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
            let id = Uuid::new_v4();
            sqlx::query(
                "INSERT INTO mobile_nodes (id, device_id, owner_id, country) VALUES ($1, $2, $3, $4)"
            )
            .bind(id)
            .bind(safe_device_id)
            .bind(auth_ctx.client_id)
            .bind(&hello.country)
            .execute(&state.app_state.db_pool)
            .await
            .context("failed to create node record")?;
            id
        }
    };

    let ct = if hello.conn_type.to_lowercase() == "mobile" {
        ConnectionType::Mobile
    } else {
        ConnectionType::WiFi
    };

    let meta = NodeMetadata {
        node_id: owner_node_id,
        ip_address: remote.ip(),
        country: hello.country.clone(),
        connection_type: ct,
        speed_mbps: hello.speed_mbps.unwrap_or(0),
    };

    Ok((owner_node_id, meta))
}

#[allow(dead_code)]
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

#[allow(dead_code)]
async fn write_len_prefixed(send: &mut SendStream, frame: &[u8]) -> anyhow::Result<()> {
    send.write_u32(frame.len() as u32).await?;
    send.write_all(frame).await?;
    Ok(())
}

#[allow(dead_code)]
pub async fn run_tuic_server(
    bind_addr: SocketAddr,
    cert_path: &str,
    key_path: &str,
    state: Arc<TuicTunnelState>,
) -> anyhow::Result<()> {
    let alpn = vec![b"byteaway-node".to_vec()];
    let server_config = load_server_config(cert_path, key_path, &alpn)?;
    let endpoint = Endpoint::server(server_config, bind_addr)
        .with_context(|| format!("failed to bind TUIC listener on {}", bind_addr))?;

    info!("TUIC v5 (QUIC-based) ingress listening on {}", bind_addr);

    while let Some(incoming) = endpoint.accept().await {
        let state_cloned = state.clone();
        tokio::spawn(async move {
            match incoming.await {
                Ok(conn) => {
                    if let Err(e) = handle_connection(conn, state_cloned).await {
                        warn!("TUIC connection ended with error: {e}");
                    }
                }
                Err(e) => warn!("TUIC handshake failed: {e}"),
            }
        });
    }

    Ok(())
}

#[allow(dead_code)]
fn load_server_config(cert_path: &str, key_path: &str, alpn: &[Vec<u8>]) -> anyhow::Result<ServerConfig> {
    let cert_chain = std::fs::read(cert_path).context("failed to read cert")?;
    let key = std::fs::read(key_path).context("failed to read key")?;

    let certs = rustls_pemfile::certs(&mut &*cert_chain)
        .collect::<Result<Vec<_>, _>>()
        .context("invalid cert")?;
    let key = rustls_pemfile::private_key(&mut &*key)
        .context("invalid key")?
        .ok_or_else(|| anyhow!("no key found"))?;

    let mut server_crypto = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .context("failed to create rustls config")?;
    
    server_crypto.alpn_protocols = alpn.to_vec();

    let mut server_config = ServerConfig::with_crypto(Arc::new(quinn::crypto::rustls::QuicServerConfig::try_from(server_crypto)?));
    let transport_config = Arc::get_mut(&mut server_config.transport).unwrap();
    transport_config.max_idle_timeout(Some(std::time::Duration::from_secs(60).try_into()?));
    transport_config.keep_alive_interval(Some(std::time::Duration::from_secs(10)));

    Ok(server_config)
}
