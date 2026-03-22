use super::registry::{NodeMetadata, NodeRegistry, ConnectionType, WsCommand};
use axum::{
    extract::{ws::{WebSocket, WebSocketUpgrade, Message}, Query, State},
    response::IntoResponse,
};
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{info, warn, error};
use uuid::Uuid;

#[derive(Deserialize)]
pub struct WsAuthQuery {
    pub device_id: Uuid,
    pub token: String,
    pub country: String,
    pub conn_type: String,
    pub speed_mbps: Option<u32>,
}

pub struct TunnelState {
    pub registry: Arc<dyn NodeRegistry>,
}

/// Axum handler: апгрейд HTTP → WebSocket для мобильных нод
pub async fn ws_upgrade_handler(
    ws: WebSocketUpgrade,
    Query(query): Query<WsAuthQuery>,
    State(state): State<Arc<TunnelState>>,
) -> impl IntoResponse {
    if query.token.is_empty() {
        return axum::http::StatusCode::UNAUTHORIZED.into_response();
    }

    let ct = if query.conn_type.eq_ignore_ascii_case("wifi") {
        ConnectionType::WiFi
    } else {
        ConnectionType::Mobile
    };

    let meta = NodeMetadata {
        node_id: query.device_id,
        ip_address: "0.0.0.0".parse().unwrap(),
        country: query.country,
        connection_type: ct,
        speed_mbps: query.speed_mbps.unwrap_or(50),
    };

    ws.on_upgrade(move |socket| handle_socket(socket, meta, state))
}

/// Бинарный протокол поверх WebSocket:
/// [1 byte: cmd][16 bytes: session_uuid][N bytes: payload]
/// Команды: 0x01=CONNECT, 0x02=DATA, 0x03=CLOSE
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

async fn handle_socket(mut socket: WebSocket, meta: NodeMetadata, state: Arc<TunnelState>) {
    let node_id = meta.node_id;
    let country = meta.country.clone();

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<WsCommand>(1024);

    if let Err(e) = state.registry.register_node(meta, cmd_tx).await {
        error!("Failed to register node {}: {:?}", node_id, e);
        let _ = socket.send(Message::Close(None)).await;
        return;
    }

    // Маппинг активных сессий: session_id → канал для отправки данных обратно в SOCKS5
    let mut sessions: HashMap<Uuid, mpsc::Sender<Vec<u8>>> = HashMap::new();
    let mut heartbeat_interval = tokio::time::interval(std::time::Duration::from_secs(30));

    loop {
        tokio::select! {
            // === Heartbeat каждые 30с ===
            _ = heartbeat_interval.tick() => {
                if let Err(e) = state.registry.heartbeat(node_id).await {
                    error!("Heartbeat failed for node {}: {:?}", node_id, e);
                    break;
                }
            }

            // === Команды от роутера (SOCKS5 → WS) ===
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(WsCommand::Open { session_id, target_addr, reply_tx }) => {
                        let frame = wire::encode(wire::CMD_CONNECT, session_id, target_addr.as_bytes());
                        if socket.send(Message::Binary(frame)).await.is_err() {
                            warn!("Failed to send CONNECT to node {}", node_id);
                            break;
                        }
                        sessions.insert(session_id, reply_tx);
                    }
                    Some(WsCommand::Data { session_id, payload }) => {
                        let frame = wire::encode(wire::CMD_DATA, session_id, &payload);
                        if socket.send(Message::Binary(frame)).await.is_err() {
                            warn!("Failed to send DATA to node {}", node_id);
                            break;
                        }
                    }
                    Some(WsCommand::Close { session_id }) => {
                        let frame = wire::encode(wire::CMD_CLOSE, session_id, &[]);
                        let _ = socket.send(Message::Binary(frame)).await;
                        sessions.remove(&session_id);
                    }
                    None => break,
                }
            }

            // === Данные от мобильной ноды (WS → SOCKS5) ===
            ws_msg = socket.recv() => {
                match ws_msg {
                    Some(Ok(Message::Binary(data))) => {
                        if let Some((cmd, sid, payload)) = wire::decode(&data) {
                            match cmd {
                                wire::CMD_DATA => {
                                    if let Some(tx) = sessions.get(&sid) {
                                        if tx.send(payload.to_vec()).await.is_err() {
                                            sessions.remove(&sid);
                                        }
                                    }
                                }
                                wire::CMD_CLOSE => {
                                    sessions.remove(&sid);
                                }
                                _ => {}
                            }
                        }
                    }
                    Some(Ok(Message::Ping(p))) => {
                        let _ = socket.send(Message::Pong(p)).await;
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        info!("Node {} disconnected", node_id);
                        break;
                    }
                    Some(Err(e)) => {
                        error!("WS error for node {}: {:?}", node_id, e);
                        break;
                    }
                    _ => {}
                }
            }
        }
    }

    let _ = state.registry.remove_node(node_id, &country).await;
}
