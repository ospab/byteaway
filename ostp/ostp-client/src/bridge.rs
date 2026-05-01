use std::time::Duration;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use bytes::Bytes;
use ostp_core::relay::RelayMessage;
use ostp_core::{NoiseRole, OstpEvent, ProtocolAction, ProtocolConfig, ProtocolMachine};
use ostp_obfuscator::TrafficProfile;
use rand::Rng;
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, watch};
use tokio::time::{interval, timeout, Instant};

use crate::app::{BridgeCommand, ConnectionStatus, UiEvent};
use crate::config::ClientConfig;
use crate::tunnel::{ProxyEvent, ProxyToClientMsg};

pub struct BridgeMetrics {
    pub bytes_sent: AtomicU64,
    pub bytes_recv: AtomicU64,
}

pub struct Bridge {
    running: bool,
    profile: TrafficProfile,
    server_addr: String,
    local_bind_addr: String,
    proxy_addr: String,
    access_key: Bytes,
    handshake_timeout_ms: u64,
    io_timeout_ms: u64,
    session_id: u32,

    metrics: Arc<BridgeMetrics>,
    sample_sent: u64,
    sample_recv: u64,
    last_rtt_ms: f64,
    last_sample_at: Instant,
}

impl Bridge {
    pub fn new(config: &ClientConfig, metrics: Arc<BridgeMetrics>) -> Result<Self> {
        let session_id: u32 = rand::thread_rng().gen();

        Ok(Self {
            running: false,
            profile: TrafficProfile::JsonRpc,
            server_addr: config.ostp.server_addr.clone(),
            local_bind_addr: config.ostp.local_bind_addr.clone(),
            proxy_addr: config.local_proxy.bind_addr.clone(),
            access_key: Bytes::from(config.ostp.access_key.clone()),
            handshake_timeout_ms: config.ostp.handshake_timeout_ms,
            io_timeout_ms: config.ostp.io_timeout_ms,
            session_id,
            metrics,
            sample_sent: 0,
            sample_recv: 0,
            last_rtt_ms: 0.0,
            last_sample_at: Instant::now(),
        })
    }

    pub async fn run(
        mut self,
        tx: mpsc::Sender<UiEvent>,
        mut bridge_rx: mpsc::Receiver<BridgeCommand>,
        mut shutdown: watch::Receiver<bool>,
        mut proxy_rx: mpsc::Receiver<ProxyEvent>,
        proxy_tx: mpsc::Sender<(u16, ProxyToClientMsg)>,
    ) -> Result<()> {
        let mut metrics_tick = interval(Duration::from_millis(500));
        let mut keepalive_tick = tokio::time::interval(Duration::from_secs(10));
        tx.send(UiEvent::Log("Bridge & TunnelManager initialized".to_string())).await.ok();

        let mut socket_opt: Option<Arc<UdpSocket>> = None;
        let mut machine_opt: Option<ProtocolMachine> = None;

        let mut udp_buf = vec![0_u8; 8192];

        loop {
            tokio::select! {
                _ = shutdown.changed() => {
                    if *shutdown.borrow() {
                        self.running = false;
                        crate::sysproxy::disable_windows_proxy();
                        socket_opt = None;
                        machine_opt = None;
                        break;
                    }
                }
                cmd = bridge_rx.recv() => {
                    match cmd {
                        Some(BridgeCommand::ToggleTunnel) => {
                            if self.running {
                                self.running = false;
                                crate::sysproxy::disable_windows_proxy();
                                socket_opt = None;
                                machine_opt = None;
                                tx.send(UiEvent::TunnelStopped).await.ok();
                                tx.send(UiEvent::Log("Tunnel stopped".to_string())).await.ok();
                            } else {
                                tx.send(UiEvent::Log("Handshaking started".to_string())).await.ok();
                                tx.send(UiEvent::Metrics { status: ConnectionStatus::Handshaking, rtt_ms: 0.0, throughput_bps: 0 }).await.ok();
                                
                                match self.perform_handshake(&tx).await {
                                    Ok((sock, mach, rtt)) => {
                                        socket_opt = Some(Arc::new(sock));
                                        machine_opt = Some(mach);
                                        self.last_rtt_ms = rtt;
                                        self.running = true;
                                        self.last_sample_at = Instant::now();
                                        
                                        crate::sysproxy::enable_windows_proxy(&self.proxy_addr);

                                        tx.send(UiEvent::Metrics {
                                            status: ConnectionStatus::Established,
                                            rtt_ms: self.last_rtt_ms,
                                            throughput_bps: 0,
                                        }).await.ok();
                                        tx.send(UiEvent::Log("Tunnel established".to_string())).await.ok();
                                    }
                                    Err(err) => {
                                        crate::sysproxy::disable_windows_proxy();
                                        tx.send(UiEvent::Log(format!("Handshake failed: {err}"))).await.ok();
                                        tx.send(UiEvent::TunnelStopped).await.ok();
                                    }
                                }
                            }
                        }
                        Some(BridgeCommand::NextProfile) => {
                            self.profile = next_profile(self.profile);
                            tx.send(UiEvent::ProfileChanged(self.profile)).await.ok();
                            tx.send(UiEvent::Log(format!("Obfuscation profile switched to {:?}", self.profile))).await.ok();
                        }
                        Some(BridgeCommand::ReloadConfig) => {
                            match ClientConfig::load_or_create_near_binary() {
                                Ok(cfg) => {
                                    self.apply_runtime_config(&cfg);
                                    tx.send(UiEvent::Log("Runtime config reloaded".to_string())).await.ok();
                                    if self.running {
                                        self.running = false;
                                        crate::sysproxy::disable_windows_proxy();
                                        socket_opt = None;
                                        machine_opt = None;
                                        // User logic handles UI restart
                                        let _ = tx.send(UiEvent::TunnelStopped).await;
                                    }
                                }
                                Err(err) => {
                                    let _ = tx.send(UiEvent::Log(format!("Config reload failed: {err}"))).await;
                                }
                            }
                        }
                        Some(BridgeCommand::Shutdown) | None => {
                            self.running = false;
                            crate::sysproxy::disable_windows_proxy();
                            break;
                        }
                    }
                }
                _ = metrics_tick.tick() => {
                    if self.running {
                        self.emit_metrics(&tx).await;
                    }
                }
                _ = keepalive_tick.tick() => {
                    if self.running {
                        if let (Some(machine), Some(socket)) = (machine_opt.as_mut(), socket_opt.as_ref()) {
                            let payload = Bytes::from(RelayMessage::KeepAlive.encode());
                            if let Ok(ProtocolAction::SendDatagram(frame)) = machine.on_event(OstpEvent::Outbound(0, payload)) {
                                let _ = socket.send(&frame).await;
                                self.metrics.bytes_sent.fetch_add(frame.len() as u64, Ordering::Relaxed);
                            }
                        }
                    }
                }
                proxy_ev = proxy_rx.recv(), if self.running => {
                    if let Some(ev) = proxy_ev {
                        if let (Some(machine), Some(socket)) = (machine_opt.as_mut(), socket_opt.as_ref()) {
                            let (stream_id, relay_msg) = match ev {
                                ProxyEvent::NewStream { stream_id, target } => (stream_id, RelayMessage::Connect(target)),
                                ProxyEvent::Data { stream_id, payload } => (stream_id, RelayMessage::Data(payload.to_vec())),
                                ProxyEvent::Close { stream_id } => (stream_id, RelayMessage::Close),
                            };
                            let out_payload = Bytes::from(relay_msg.encode());
                            match machine.on_event(OstpEvent::Outbound(stream_id, out_payload)) {
                                Ok(ProtocolAction::SendDatagram(frame)) => {
                                    if socket.send(&frame).await.is_ok() {
                                        self.metrics.bytes_sent.fetch_add(frame.len() as u64, Ordering::Relaxed);
                                    }
                                }
                                Err(e) => {
                                    let _ = tx.send(UiEvent::Log(format!("Protocol error packing TCP: {e}"))).await;
                                }
                                _ => {}
                            }
                        } else {
                            // Drop it, not connected
                            if let ProxyEvent::NewStream { stream_id, .. } = ev {
                                let _ = proxy_tx.send((stream_id, ProxyToClientMsg::Error("tunnel stopped".into()))).await;
                            }
                        }
                    }
                }
                recv_res = async {
                    if let Some(s) = socket_opt.as_ref() {
                        s.recv(&mut udp_buf).await
                    } else {
                        std::future::pending().await
                    }
                }, if self.running => {
                    match recv_res {
                        Ok(n) => {
                            self.metrics.bytes_recv.fetch_add(n as u64, Ordering::Relaxed);
                            if let Some(machine) = machine_opt.as_mut() {
                                let inbound = Bytes::copy_from_slice(&udp_buf[..n]);
                                match machine.on_event(OstpEvent::Inbound(inbound)) {
                                    Ok(ProtocolAction::DeliverApp(stream_id, dec_payload)) => {
                                        if let Ok(relay_msg) = RelayMessage::decode(&dec_payload) {
                                            match relay_msg {
                                                RelayMessage::ConnectOk => {
                                                    let _ = proxy_tx.send((stream_id, ProxyToClientMsg::ConnectOk)).await;
                                                }
                                                RelayMessage::Data(data) => {
                                                    let _ = proxy_tx.send((stream_id, ProxyToClientMsg::Data(Bytes::from(data)))).await;
                                                }
                                                RelayMessage::Close => {
                                                    let _ = proxy_tx.send((stream_id, ProxyToClientMsg::Close)).await;
                                                }
                                                RelayMessage::Error(msg) => {
                                                    let _ = proxy_tx.send((stream_id, ProxyToClientMsg::Error(msg))).await;
                                                }
                                                RelayMessage::KeepAlive | RelayMessage::Connect(_) => {}
                                            }
                                        }
                                    }
                                    Ok(ProtocolAction::SendDatagram(frame)) => {
                                        if let Some(socket) = socket_opt.as_ref() {
                                            let _ = socket.send(&frame).await;
                                            self.metrics.bytes_sent.fetch_add(frame.len() as u64, Ordering::Relaxed);
                                        }
                                    }
                                    Ok(_) => {}
                                    Err(e) => {
                                        let _ = tx.send(UiEvent::Log(format!("Protocol decrypt error: {e}"))).await;
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            // Handle WSAECONNRESET from Windows, ignore it to prevent loop breaking
                            if e.kind() == std::io::ErrorKind::ConnectionReset {
                                continue;
                            }
                            let _ = tx.send(UiEvent::Log(format!("UDP socket err: {e}"))).await;
                            self.running = false;
                            crate::sysproxy::disable_windows_proxy();
                            socket_opt = None;
                            machine_opt = None;
                            let _ = tx.send(UiEvent::TunnelStopped).await;
                        }
                    }
                }
            }
        }

        tx.send(UiEvent::Log("Bridge stopped".to_string())).await.ok();
        Ok(())
    }

    async fn emit_metrics(&mut self, tx: &mpsc::Sender<UiEvent>) {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last_sample_at).as_secs_f64().max(0.001);
        self.last_sample_at = now;

        let cur_sent = self.metrics.bytes_sent.load(Ordering::Relaxed);
        let cur_recv = self.metrics.bytes_recv.load(Ordering::Relaxed);

        let sent_delta = cur_sent.saturating_sub(self.sample_sent);
        let recv_delta = cur_recv.saturating_sub(self.sample_recv);
        
        self.sample_sent = cur_sent;
        self.sample_recv = cur_recv;

        let outgoing = (sent_delta as f64 / elapsed) as u64;
        let incoming = (recv_delta as f64 / elapsed) as u64;
        let throughput = incoming.saturating_add(outgoing);

        tx.send(UiEvent::Traffic { incoming_bps: incoming, outgoing_bps: outgoing }).await.ok();
        tx.send(UiEvent::Metrics {
            status: ConnectionStatus::Established,
            rtt_ms: self.last_rtt_ms,
            throughput_bps: throughput,
        }).await.ok();
    }

    async fn perform_handshake(&mut self, tx: &mpsc::Sender<UiEvent>) -> Result<(UdpSocket, ProtocolMachine, f64)> {
        let mut machine = ProtocolMachine::new(ProtocolConfig {
            role: NoiseRole::Initiator,
            static_noise_key: vec![0_u8; 32],
            remote_static_pubkey: None,
            session_id: self.session_id,
            handshake_payload: self.access_key.to_vec(),
            max_padding: 256,
        })?;

        let socket = UdpSocket::bind(&self.local_bind_addr)
            .await
            .with_context(|| format!("failed to bind local udp {}", self.local_bind_addr))?;
        socket
            .connect(&self.server_addr)
            .await
            .with_context(|| format!("failed to connect udp to {}", self.server_addr))?;

        tx.send(UiEvent::Log(format!("Connected UDP to {}", self.server_addr))).await.ok();

        let start = Instant::now();
        let action = machine.on_event(OstpEvent::Start)?;
        let handshake_frame = match action {
            ProtocolAction::SendDatagram(frame) => frame,
            _ => anyhow::bail!("protocol did not emit handshake datagram"),
        };
        socket.send(&handshake_frame).await?;
        self.metrics.bytes_sent.fetch_add(handshake_frame.len() as u64, Ordering::Relaxed);

        let mut buf = vec![0_u8; 4096];
        let size = timeout(
            Duration::from_millis(self.handshake_timeout_ms.max(1)),
            socket.recv(&mut buf),
        )
        .await
        .context("handshake timeout waiting server response")??;
        self.metrics.bytes_recv.fetch_add(size as u64, Ordering::Relaxed);

        let inbound = Bytes::copy_from_slice(&buf[..size]);
        machine.on_event(OstpEvent::Inbound(inbound))?;
        let rtt_ms = start.elapsed().as_secs_f64() * 1000.0;
        
        // Success
        self.session_id = rand::thread_rng().gen(); // Prep next ID for next start
        Ok((socket, machine, rtt_ms))
    }

    fn apply_runtime_config(&mut self, cfg: &ClientConfig) {
        self.server_addr = cfg.ostp.server_addr.clone();
        self.local_bind_addr = cfg.ostp.local_bind_addr.clone();
        self.proxy_addr = cfg.local_proxy.bind_addr.clone();
        self.access_key = Bytes::from(cfg.ostp.access_key.clone());
        self.handshake_timeout_ms = cfg.ostp.handshake_timeout_ms;
        self.io_timeout_ms = cfg.ostp.io_timeout_ms;
    }
}

fn next_profile(current: TrafficProfile) -> TrafficProfile {
    match current {
        TrafficProfile::JsonRpc => TrafficProfile::HttpsBurst,
        TrafficProfile::HttpsBurst => TrafficProfile::VideoStream,
        TrafficProfile::VideoStream => TrafficProfile::JsonRpc,
    }
}
