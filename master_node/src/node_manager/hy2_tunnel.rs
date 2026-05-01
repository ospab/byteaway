use super::registry::{ConnectionType, NodeMetadata, NodeRegistry, WsCommand};
use anyhow::{anyhow, Context};
use dashmap::DashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tracing::{info, warn};
use uuid::Uuid;

#[allow(dead_code)]
pub struct Hy2TunnelState {
    pub registry: Arc<dyn NodeRegistry>,
    pub app_state: Arc<crate::state::AppState>,
}

#[derive(Debug, serde::Deserialize)]
#[allow(dead_code)]
struct Hy2Hello {
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
async fn authenticate_and_build_meta(
    _state: &Hy2TunnelState,
    hello: &Hy2Hello,
    remote: SocketAddr,
) -> anyhow::Result<(Uuid, NodeMetadata)> {
    let node_id = Uuid::new_v4();
    let ip: std::net::IpAddr = remote.ip();

    let conn_type = match hello.conn_type.to_lowercase().as_str() {
        "wifi" | "wi-fi" => ConnectionType::WiFi,
        "mobile" | "cellular" => ConnectionType::Mobile,
        _ => ConnectionType::WiFi,
    };

    let meta = NodeMetadata {
        node_id,
        ip_address: ip,
        country: hello.country.clone(),
        connection_type: conn_type,
        speed_mbps: hello.speed_mbps.unwrap_or(50),
    };

    Ok((node_id, meta))
}

#[allow(dead_code)]
async fn read_frame<R: tokio::io::AsyncRead + Unpin + Sized>(reader: &mut R) -> anyhow::Result<Option<Vec<u8>>> {
    let mut len_buf = [0u8; 2];
    match reader.read_exact(&mut len_buf).await {
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e.into()),
    }

    let len = u16::from_be_bytes(len_buf) as usize;
    let mut data = vec![0u8; len];
    reader.read_exact(&mut data).await?;
    Ok(Some(data))
}

#[allow(dead_code)]
async fn write_frame<W: tokio::io::AsyncWrite + Unpin + Sized>(writer: &mut W, data: &[u8]) -> anyhow::Result<()> {
    let len = (data.len() as u16).to_be_bytes();
    writer.write_all(&len).await?;
    writer.write_all(data).await?;
    writer.flush().await?;
    Ok(())
}

#[allow(dead_code)]
pub async fn run_hy2_server(
    bind_addr: SocketAddr,
    state: Arc<Hy2TunnelState>,
) -> anyhow::Result<()> {
    let listener = TcpListener::bind(bind_addr)
        .await
        .with_context(|| format!("failed to bind HY2 listener on {}", bind_addr))?;

    info!("HY2 ingress listening on {}", bind_addr);

    loop {
        let (stream, remote) = listener.accept().await?;
        let state_cloned = state.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_connection(stream, remote, state_cloned).await {
                warn!("HY2 connection error: {}", e);
            }
        });
    }
}

#[allow(dead_code)]
async fn handle_connection(
    stream: tokio::net::TcpStream,
    remote: SocketAddr,
    state: Arc<Hy2TunnelState>,
) -> anyhow::Result<()> {
    let (reader, writer) = stream.into_split();
    let mut reader = tokio::io::BufReader::new(reader);
    let writer = Arc::new(tokio::sync::Mutex::new(tokio::io::BufWriter::new(writer)));
    let writer_clone = writer.clone();

    let hello_frame = read_frame(&mut reader).await
        .context("failed to read hello frame")?
        .ok_or_else(|| anyhow!("empty hello frame"))?;

    let hello: Hy2Hello = serde_json::from_slice(&hello_frame)
        .context("invalid hello json")?;

    let (node_uuid, meta) = authenticate_and_build_meta(&state, &hello, remote).await?;

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<WsCommand>(1024);
    state
        .registry
        .register_node(meta.clone(), cmd_tx)
        .await
        .context("failed to register node")?;

    info!("HY2 node connected: {} country={} remote={}", node_uuid, meta.country, remote);

    let sessions = Arc::new(DashMap::<Uuid, mpsc::Sender<Vec<u8>>>::new());

    let sessions_reader = sessions.clone();
    let reader_task = tokio::spawn(async move {
        loop {
            match read_frame(&mut reader).await {
                Ok(Some(data)) => {
                    if let Some((cmd, sid, payload)) = wire::decode(&data) {
                        match cmd {
                            wire::CMD_DATA => {
                                if let Some(tx) = sessions_reader.get(&sid) {
                                    if let Err(e) = tx.try_send(payload.to_vec()) {
                                        warn!("[{}] HY2 -> Router: SEND FAILED: {}", &sid.to_string()[..8], e);
                                    }
                                }
                            }
                            wire::CMD_CLOSE => {
                                info!("[{}] HY2 CMD_CLOSE received", &sid.to_string()[..8]);
                                sessions_reader.remove(&sid);
                            }
                            _ => {}
                        }
                    }
                }
                Ok(None) => break,
                Err(e) => {
                    warn!("HY2 read error: {}", e);
                    break;
                }
            }
        }
    });

    let sessions_writer = sessions.clone();
    let cmd_task = tokio::spawn(async move {
        while let Some(cmd) = cmd_rx.recv().await {
            let mut w = writer_clone.lock().await;
            match cmd {
                WsCommand::Open { session_id, target_addr, reply_tx } => {
                    let _ = sessions_writer.insert(session_id, reply_tx);
                    let open_msg = format!("OPEN:{}", target_addr);
                    let frame = wire::encode(wire::CMD_CONNECT, session_id, open_msg.as_bytes());
                    if write_frame(&mut *w, &frame).await.is_err() {
                        break;
                    }
                }
                WsCommand::Data { session_id, payload } => {
                    let frame = wire::encode(wire::CMD_DATA, session_id, &payload);
                    if write_frame(&mut *w, &frame).await.is_err() {
                        break;
                    }
                }
                WsCommand::Close { session_id } => {
                    sessions_writer.remove(&session_id);
                    let frame = wire::encode(wire::CMD_CLOSE, session_id, &[]);
                    let _ = write_frame(&mut *w, &frame).await;
                }
            }
        }
    });

    tokio::select! {
        _ = reader_task => {}
        _ = cmd_task => {}
    }

    info!("HY2 node disconnected: {}", node_uuid);
    Ok(())
}
