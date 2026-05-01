use crate::node_manager::registry::NodeRegistry;
use anyhow::{anyhow, Result, Context};
use bytes::Bytes;
use dashmap::DashMap;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, Mutex};
use tracing::{info, warn};
use uuid::Uuid;
use crate::node_manager::registry::{ConnectionType, TunnelCommand, NodeMetadata};
use sqlx::Row;

use ostp_core::{NoiseRole, ProtocolAction, ProtocolConfig, ProtocolMachine, OstpEvent};
use ostp_core::relay::RelayMessage;

use crate::state::AppState;

#[allow(dead_code)]
pub struct PeerState {
    pub machine: ProtocolMachine,
    pub last_addr: SocketAddr,
    pub node_id: Uuid,
    pub _country: String,
    pub _ostp_session_id: u32,
    /// Mapping of internal OSTP stream_id (u16) to Master Node session Uuid
    pub streams: HashMap<u16, mpsc::Sender<Vec<u8>>>,
    /// Reverse mapping for outgoing commands (Uuid -> stream_id)
    pub rev_streams: HashMap<Uuid, u16>,
    pub next_stream_id: u16,
}

#[allow(dead_code)]
pub struct OstpDispatcher {
    /// key: OSTP session_id (u32)
    peer_machines: Arc<DashMap<u32, Arc<Mutex<PeerState>>>>,
    machine_config: ProtocolConfig,
    app_state: Arc<AppState>,
    socket: Arc<UdpSocket>,
}

#[allow(dead_code)]
pub enum DispatchOutcome {
    Unauthorized,
    Accepted {
        response: Option<Bytes>,
        peer_addr: SocketAddr,
    },
}

#[allow(dead_code)]
impl OstpDispatcher {
    #[allow(dead_code)]
    pub fn new(machine_config: ProtocolConfig, app_state: Arc<AppState>, socket: Arc<UdpSocket>) -> Self {
        Self {
            peer_machines: Arc::new(DashMap::new()),
            machine_config,
            app_state,
            socket,
        }
    }

    #[allow(dead_code)]
    pub async fn on_datagram(&self, peer: SocketAddr, packet: Bytes) -> Result<DispatchOutcome> {
        if packet.len() < 4 {
            return Ok(DispatchOutcome::Unauthorized);
        }
        let ostp_session_id = u32::from_be_bytes([packet[0], packet[1], packet[2], packet[3]]);

        if !self.peer_machines.contains_key(&ostp_session_id) {
            let mut cfg = self.machine_config.clone();
            cfg.session_id = ostp_session_id;
            cfg.handshake_payload = vec![];
            
            let mut machine = ProtocolMachine::new(cfg).map_err(|e| anyhow!(e))?;
            let action = machine.on_event(OstpEvent::Inbound(packet.clone())).map_err(|e| anyhow!(e))?;

            if let ProtocolAction::HandshakePayload(payload, response_opt) = action {
                if let Ok(json_str) = std::str::from_utf8(&payload) {
                    let (token, country, conn_type, hwid) = match serde_json::from_str::<serde_json::Value>(json_str) {
                        Ok(v) => (
                            v["token"].as_str().unwrap_or("").to_string(),
                            v["country"].as_str().unwrap_or("RU").to_string(),
                            v["conn_type"].as_str().unwrap_or("wifi").to_string(),
                            v["hwid"].as_str().map(|s| s.to_string()),
                        ),
                        Err(_) => (json_str.to_string(), "RU".to_string(), "wifi".to_string(), None),
                    };

                    match self.app_state.authenticator.authenticate(&token, &peer.ip().to_string()).await {
                        Ok(auth_ctx) => {
                            // Проверяем HWID если он предоставлен
                            if let Some(device_hwid) = hwid {
                                let hwid_check = sqlx::query(
                                    "SELECT id, is_blocked FROM devices WHERE client_id = $1 AND hwid = $2"
                                )
                                .bind(auth_ctx.client_id)
                                .bind(&device_hwid)
                                .fetch_optional(&self.app_state.db_pool)
                                .await;

                                match hwid_check {
                                    Ok(Some(row)) => {
                                        let is_blocked: bool = row.try_get("is_blocked").unwrap_or(false);
                                        if is_blocked {
                                            warn!("OSTP Auth failed for {}: device HWID {} is blocked", peer, device_hwid);
                                            return Ok(DispatchOutcome::Unauthorized);
                                        }
                                        info!("OSTP HWID verified: client={}, hwid={}", auth_ctx.client_id, device_hwid);
                                    }
                                    Ok(None) => {
                                        warn!("OSTP Auth failed for {}: device HWID {} not registered for client {}", peer, device_hwid, auth_ctx.client_id);
                                        return Ok(DispatchOutcome::Unauthorized);
                                    }
                                    Err(e) => {
                                        warn!("OSTP HWID check failed for {}: {}", peer, e);
                                        // Продолжаем без HWID проверки при ошибке БД
                                    }
                                }
                            }

                            let node_id = auth_ctx.client_id;
                            info!("OSTP Node {} registered via session {}", node_id, ostp_session_id);
                            
                            let (cmd_tx, mut cmd_rx) = mpsc::channel::<TunnelCommand>(1024);
                            let ct = if conn_type.to_lowercase() == "wifi" { ConnectionType::WiFi } else { ConnectionType::Mobile };
                            
                            let meta = NodeMetadata {
                                node_id,
                                ip_address: peer.ip(),
                                country: country.clone(),
                                connection_type: ct,
                                speed_mbps: 50,
                                tunnel_protocol: "OSTP".to_string(),
                            };

                            NodeRegistry::register_node(&*self.app_state.registry, meta, cmd_tx).await.map_err(|e| anyhow!(e))?;

                            let peer_state = Arc::new(Mutex::new(PeerState {
                                machine,
                                last_addr: peer,
                                node_id,
                                _country: country.clone(),
                                _ostp_session_id: ostp_session_id,
                                streams: HashMap::new(),
                                rev_streams: HashMap::new(),
                                next_stream_id: 1,
                            }));
                            
                            self.peer_machines.insert(ostp_session_id, peer_state.clone());

                            // Spawn a task to bridge Registry commands to this OSTP session
                            let socket_inner = self.socket.clone();
                            let app_state_inner = self.app_state.clone();
                            let peer_state_inner = peer_state.clone();
                            let peer_machines_inner = self.peer_machines.clone();
                            
                            tokio::spawn(async move {
                                while let Some(cmd) = cmd_rx.recv().await {
                                    match cmd {
                                        TunnelCommand::Open { session_id, target_addr, reply_tx } => {
                                            let mut ps = peer_state_inner.lock().await;
                                            let stream_id = ps.next_stream_id;
                                            ps.next_stream_id += 1;
                                            
                                            // Create per-session worker for non-blocking delivery
                                            let (session_tx, mut session_rx) = mpsc::channel::<Vec<u8>>(1024);
                                            tokio::spawn(async move {
                                                while let Some(payload) = session_rx.recv().await {
                                                    if reply_tx.send(payload).await.is_err() {
                                                        break;
                                                    }
                                                }
                                            });
                                            
                                            ps.streams.insert(stream_id, session_tx);
                                            ps.rev_streams.insert(session_id, stream_id);
                                            
                                            let relay_msg = RelayMessage::Connect(target_addr);
                                            let encoded = relay_msg.encode();
                                            if let Ok(action) = ps.machine.on_event(OstpEvent::Outbound(stream_id, encoded.into())) {
                                                if let ProtocolAction::SendDatagram(frame) = action {
                                                    let _ = socket_inner.send_to(&frame, ps.last_addr).await;
                                                }
                                            }
                                        }
                                        TunnelCommand::Data { session_id, payload } => {
                                            let mut ps = peer_state_inner.lock().await;
                                            if let Some(&stream_id) = ps.rev_streams.get(&session_id) {
                                                let relay_msg = RelayMessage::Data(payload);
                                                let encoded = relay_msg.encode();
                                                if let Ok(action) = ps.machine.on_event(OstpEvent::Outbound(stream_id, encoded.into())) {
                                                    if let ProtocolAction::SendDatagram(frame) = action {
                                                        let _ = socket_inner.send_to(&frame, ps.last_addr).await;
                                                    }
                                                }
                                            }
                                        }
                                        TunnelCommand::Close { session_id } => {
                                            let mut ps = peer_state_inner.lock().await;
                                            if let Some(stream_id) = ps.rev_streams.remove(&session_id) {
                                                ps.streams.remove(&stream_id);
                                                let relay_msg = RelayMessage::Close;
                                                let encoded = relay_msg.encode();
                                                if let Ok(action) = ps.machine.on_event(OstpEvent::Outbound(stream_id, encoded.into())) {
                                                    if let ProtocolAction::SendDatagram(frame) = action {
                                                        let _ = socket_inner.send_to(&frame, ps.last_addr).await;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                let _ = NodeRegistry::remove_node(&*app_state_inner.registry, node_id, &country).await;
                                peer_machines_inner.remove(&ostp_session_id);
                            });

                            return Ok(DispatchOutcome::Accepted {
                                response: response_opt,
                                peer_addr: peer,
                            });
                        }
                        Err(e) => {
                            warn!("OSTP Auth failed for {}: {}", peer, e);
                        }
                    }
                }
            }
            return Ok(DispatchOutcome::Unauthorized);
        }

        let peer_state_arc = self.peer_machines.get(&ostp_session_id).context("missing peer state")?.clone();
        let mut ps = peer_state_arc.lock().await;
        ps.last_addr = peer;

        let action = ps.machine.on_event(OstpEvent::Inbound(packet)).map_err(|e| anyhow!(e))?;
        match action {
            ProtocolAction::SendDatagram(frame) => {
                return Ok(DispatchOutcome::Accepted {
                    response: Some(frame),
                    peer_addr: peer,
                });
            }
            ProtocolAction::DeliverApp(stream_id, payload) => {
                if let Ok(relay_msg) = RelayMessage::decode(&payload) {
                    match relay_msg {
                        RelayMessage::Data(data) => {
                            if let Some(tx) = ps.streams.get(&stream_id) {
                                // Non-blocking delivery
                                if let Err(mpsc::error::TrySendError::Full(_)) = tx.try_send(data) {
                                    warn!("OSTP reader: session buffer full, dropping frame: node={} stream={}", ps.node_id, stream_id);
                                }
                            }
                        }
                        RelayMessage::Close => {
                            if let Some(tx) = ps.streams.remove(&stream_id) {
                                if let Some(sid_uuid) = ps.rev_streams.iter().find(|(_, &v)| v == stream_id).map(|(k, _)| *k) {
                                    ps.rev_streams.remove(&sid_uuid);
                                }
                                drop(tx);
                            }
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }

        Ok(DispatchOutcome::Accepted {
            response: None,
            peer_addr: peer,
        })
    }
}

#[allow(dead_code)]
pub async fn run_ostp_server(addr: SocketAddr, app_state: Arc<AppState>) -> Result<()> {
    let socket = Arc::new(UdpSocket::bind(addr).await?);
    info!("OSTP Server listening on UDP {}", addr);

    let private_key = match base64::Engine::decode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, &app_state.reality_private_key) {
        Ok(k) => k,
        Err(_) => vec![0_u8; 32],
    };

    let machine_cfg = ProtocolConfig {
        role: NoiseRole::Responder,
        static_noise_key: private_key,
        remote_static_pubkey: None,
        session_id: 0,
        handshake_payload: vec![],
        max_padding: 256,
    };

    let dispatcher = Arc::new(OstpDispatcher::new(machine_cfg, app_state.clone(), socket.clone()));
    let mut buf = vec![0_u8; 2048];

    loop {
        let (size, peer) = socket.recv_from(&mut buf).await?;
        let packet = Bytes::copy_from_slice(&buf[..size]);
        
        let dispatcher_inner = dispatcher.clone();
        let socket_inner = socket.clone();
        tokio::spawn(async move {
            match dispatcher_inner.on_datagram(peer, packet).await {
                Ok(DispatchOutcome::Accepted { response, peer_addr }) => {
                    if let Some(resp) = response {
                        let _ = socket_inner.send_to(&resp, peer_addr).await;
                    }
                }
                Err(e) => {
                    warn!("OSTP error processing datagram from {}: {}", peer, e);
                }
                _ => {}
            }
        });
    }
}
