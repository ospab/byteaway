use super::registry::{NodeMetadata, NodeRegistry, TunnelCommand, ConnectionType};
use crate::state::AppState;
use axum::extract::ws::{Message, WebSocket};
use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{error, info, warn};
use uuid::Uuid;
use futures_util::{StreamExt, SinkExt};

pub struct TunnelState {
    pub registry: Arc<dyn NodeRegistry>,
    pub _app_state: Arc<AppState>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct WsHello {
    pub device_id: String,
    pub token: String,
    pub country: String,
    pub conn_type: String,
    pub speed_mbps: Option<u32>,
}

use super::wire;

pub async fn ws_upgrade_handler(
    ws: axum::extract::WebSocketUpgrade,
    axum::extract::Query(hello): axum::extract::Query<WsHello>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
    axum::extract::State(state): axum::extract::State<Arc<TunnelState>>,
) -> impl axum::response::IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, hello, addr, state))
}

pub async fn handle_socket(socket: WebSocket, hello: WsHello, remote_addr: std::net::SocketAddr, state: Arc<TunnelState>) {
    let (mut sink, mut stream) = socket.split();

    // 1. Auth & Register
    let safe_device_id = hello.device_id.trim();
    
    // Authenticate token
    let auth_ctx = state._app_state.authenticator
        .authenticate(&hello.token, &remote_addr.ip().to_string())
        .await;
    
    let auth_ctx = match auth_ctx {
        Ok(ctx) => ctx,
        Err(_) => {
            error!("WS auth failed: remote={} device_id_len={}", remote_addr, safe_device_id.len());
            let _ = sink.close().await;
            return;
        }
    };

    // Lookup or create node
    let owner_by_device: Result<Option<Uuid>, sqlx::Error> = sqlx::query_scalar(
        "SELECT id FROM mobile_nodes WHERE device_id = $1"
    )
    .bind(safe_device_id)
    .fetch_optional(&state._app_state.db_pool)
    .await;

    let owner_node_id = match owner_by_device {
        Ok(Some(v)) => v,
        Ok(None) => {
            let id = Uuid::new_v4();
            if let Err(e) = sqlx::query(
                "INSERT INTO mobile_nodes (id, device_id, owner_id, country) VALUES ($1, $2, $3, $4)"
            )
            .bind(id)
            .bind(safe_device_id)
            .bind(auth_ctx.client_id)
            .bind(&hello.country)
            .execute(&state._app_state.db_pool)
            .await
            {
                error!("Failed to create node record: {:?}", e);
                let _ = sink.close().await;
                return;
            }
            id
        }
        Err(e) => {
            error!("Device lookup failed: {:?}", e);
            let _ = sink.close().await;
            return;
        }
    };

    let meta = NodeMetadata {
        node_id: owner_node_id,
        ip_address: remote_addr.ip(), 
        country: hello.country.clone(),
        connection_type: if hello.conn_type.to_lowercase() == "mobile" { ConnectionType::Mobile } else { ConnectionType::WiFi },
        speed_mbps: hello.speed_mbps.unwrap_or(0),
        tunnel_protocol: "WS".to_string(),
    };

    let country_for_log = meta.country.clone();
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<TunnelCommand>(1024);
    if let Err(e) = state.registry.register_node(meta, cmd_tx).await {
        error!("Failed to register node {}: {:?}", owner_node_id, e);
        return;
    }

    info!("WS node connected: {} country={} remote={}", owner_node_id, country_for_log, remote_addr);

    // sessions: mapping of session_id to internal_tx (for delivery from Tunnel -> SOCKS5)
    let sessions = Arc::new(DashMap::<Uuid, mpsc::Sender<Vec<u8>>>::new());

    // Task 1: Tunnel Reader (WS -> SOCKS5)
    let sessions_reader = sessions.clone();
    let node_id_reader = owner_node_id;
    let reader_task = tokio::spawn(async move {
        while let Some(msg) = stream.next().await {
            match msg {
                Ok(Message::Binary(data)) => {
                    if let Some((cmd, sid, payload)) = wire::decode(&data) {
                        match cmd {
                            wire::CMD_DATA => {
                                if let Some(tx) = sessions_reader.get(&sid) {
                                    if let Err(mpsc::error::TrySendError::Full(_)) = tx.try_send(payload.to_vec()) {
                                        warn!("WS reader: session buffer full, dropping frame: node={} sid={}", node_id_reader, sid);
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
                Ok(Message::Close(_)) | Err(_) => break,
                _ => {}
            }
        }
        info!("WS node reader ended: {}", node_id_reader);
    });

    // Task 2: Tunnel Writer (SOCKS5 -> WS) + Heartbeat
    let sessions_writer = sessions.clone();
    let country_writer = hello.country.clone();
    let mut heartbeat_interval = tokio::time::interval(std::time::Duration::from_secs(30));
    
    loop {
        tokio::select! {
            _ = heartbeat_interval.tick() => {
                if let Err(e) = state.registry.heartbeat(owner_node_id).await {
                    error!("Heartbeat failed for node {}: {:?}", owner_node_id, e);
                    break;
                }
            }

            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(TunnelCommand::Open { session_id, target_addr, reply_tx }) => {
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
                        if sink.send(Message::Binary(frame)).await.is_err() { break; }
                    }
                    Some(TunnelCommand::Data { session_id, payload }) => {
                        let frame = wire::encode(wire::CMD_DATA, session_id, &payload);
                        if sink.send(Message::Binary(frame)).await.is_err() { break; }
                    }
                    Some(TunnelCommand::Close { session_id }) => {
                        let frame = wire::encode(wire::CMD_CLOSE, session_id, &[]);
                        let _ = sink.send(Message::Binary(frame)).await;
                        sessions_writer.remove(&session_id);
                    }
                    None => break,
                }
            }
        }
    }

    let _ = state.registry.remove_node(owner_node_id, &country_writer).await;
    info!("WS node disconnected: {}", owner_node_id);
    reader_task.abort();
}
