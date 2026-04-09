use std::collections::HashMap;
use std::sync::Arc;
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex};
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};
use uuid::Uuid;
use tracing::{info, warn, error};

// Wire protocol constants
const CMD_CONNECT: u8 = 0x01;
const CMD_DATA: u8 = 0x02;
const CMD_CLOSE: u8 = 0x03;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    let master_url = std::env::var("MASTER_URL").unwrap_or_else(|_| "ws://127.0.0.1:3000/ws".to_string());
    let token = std::env::var("NODE_TOKEN").unwrap_or_else(|_| "node_test_token".to_string());
    let device_id = std::env::var("DEVICE_ID").unwrap_or_else(|_| Uuid::new_v4().to_string());
    let country = std::env::var("COUNTRY").unwrap_or_else(|_| "US".to_string());

    let ws_url = format!(
        "{}?device_id={}&token={}&country={}&conn_type=wifi&speed_mbps=100",
        master_url, device_id, token, country
    );

    info!("Connecting to master at {}...", master_url);

    let (ws_stream, _) = connect_async(&ws_url).await?;
    let (mut ws_tx, mut ws_rx) = ws_stream.split();

    // sessions: session_id -> sender to TCP forwarder
    let sessions: Arc<Mutex<HashMap<Uuid, mpsc::Sender<Vec<u8>>>>> = Arc::new(Mutex::new(HashMap::new()));

    // ws_back: data from TCP forwarders back to WebSocket
    let (ws_back_tx, mut ws_back_rx) = mpsc::channel::<Message>(1024);

    // Forwarding loop: ws_back_rx -> ws_tx (WebSocket)
    let ws_forward_handle = tokio::spawn(async move {
        while let Some(msg) = ws_back_rx.recv().await {
            if ws_tx.send(msg).await.is_err() {
                break;
            }
        }
    });

    info!("Node registered and tunnel active.");

    while let Some(msg) = ws_rx.next().await {
        let msg = match msg {
            Ok(Message::Binary(data)) if data.len() >= 17 => data,
            Ok(Message::Ping(p)) => {
                let _ = ws_back_tx.send(Message::Pong(p)).await;
                continue;
            }
            Ok(Message::Close(_)) => break,
            Ok(_) => continue,
            Err(e) => {
                error!("WebSocket receive error: {}", e);
                break;
            }
        };

        let cmd = msg[0];
        let session_id = Uuid::from_bytes(msg[1..17].try_into().unwrap());
        let payload = &msg[17..];

        match cmd {
            CMD_CONNECT => {
                let target_addr = String::from_utf8_lossy(payload).to_string();
                let sessions_clone = sessions.clone();
                let ws_back_tx_clone = ws_back_tx.clone();

                tokio::spawn(async move {
                    if let Err(e) = handle_new_session(session_id, target_addr, sessions_clone, ws_back_tx_clone).await {
                        warn!("Session {} failed: {}", session_id, e);
                    }
                });
            }
            CMD_DATA => {
                let sessions_guard = sessions.lock().await;
                if let Some(tx) = sessions_guard.get(&session_id) {
                    let _ = tx.send(payload.to_vec()).await;
                }
            }
            CMD_CLOSE => {
                let mut sessions_guard = sessions.lock().await;
                sessions_guard.remove(&session_id);
            }
            _ => {}
        }
    }

    ws_forward_handle.abort();
    Ok(())
}

async fn handle_new_session(
    session_id: Uuid,
    target_addr: String,
    sessions: Arc<Mutex<HashMap<Uuid, mpsc::Sender<Vec<u8>>>>>,
    ws_back_tx: mpsc::Sender<Message>,
) -> anyhow::Result<()> {
    let tcp_stream = TcpStream::connect(&target_addr).await?;
    let (mut tcp_rx, mut tcp_tx) = tcp_stream.into_split();

    let (session_tx, mut session_rx) = mpsc::channel::<Vec<u8>>(1024);
    {
        sessions.lock().await.insert(session_id, session_tx);
    }

    // TCP Write Task
    let mut forward_task = tokio::spawn(async move {
        while let Some(data) = session_rx.recv().await {
            if tcp_tx.write_all(&data).await.is_err() {
                break;
            }
        }
    });

    // TCP Read Task
    let ws_tx_clone = ws_back_tx.clone();
    let mut backward_task = tokio::spawn(async move {
        let mut buf = [0u8; 16384];
        loop {
            match tcp_rx.read(&mut buf).await {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    let mut frame = Vec::with_capacity(17 + n);
                    frame.push(CMD_DATA);
                    frame.extend_from_slice(session_id.as_bytes());
                    frame.extend_from_slice(&buf[..n]);
                    if ws_tx_clone.send(Message::Binary(frame)).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    tokio::select! {
        _ = &mut forward_task => {}
        _ = &mut backward_task => {}
    }

    sessions.lock().await.remove(&session_id);

    let mut close_frame = Vec::with_capacity(17);
    close_frame.push(CMD_CLOSE);
    close_frame.extend_from_slice(session_id.as_bytes());
    let _ = ws_back_tx.send(Message::Binary(close_frame)).await;

    Ok(())
}
