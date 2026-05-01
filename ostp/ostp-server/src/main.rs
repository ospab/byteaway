mod auth_store;
mod config;
mod dispatcher;
mod signal;
mod tui;

use anyhow::Result;
use bytes::Bytes;
use std::collections::HashMap;
use std::time::Duration;
use auth_store::AccessKeyStore;
use config::ServerConfig;
use dispatcher::{DispatchOutcome, Dispatcher};
use ostp_core::relay::RelayMessage;
use ostp_core::{NoiseRole, ProtocolConfig};
use signal::wait_for_shutdown_signal;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpStream, UdpSocket};
use tokio::sync::mpsc;
use tui::{UiCommand, UiEvent};

#[tokio::main]
async fn main() -> Result<()> {
    let no_tui = std::env::args().any(|a| a == "--no-tui");
    let cfg = ServerConfig::load_or_create_near_binary()?;
    let access_keys_path = cfg.access_keys_path_near_binary()?;
    let access_store = AccessKeyStore::load_or_create(access_keys_path)?;

    println!("[ostp-server] config loaded from binary directory");
    println!("[ostp-server] bind_addr={}", cfg.bind_addr);
    println!("[ostp-server] access_keys_file={}", cfg.access_keys_file);
    println!("[ostp-server] access_keys={}", access_store.count());

    let machine_cfg = ProtocolConfig {
        role: NoiseRole::Responder,
        static_noise_key: vec![0_u8; 32],
        remote_static_pubkey: None,
        session_id: Default::default(), // Populated dynamically by dispatcher
        handshake_payload: vec![],
        max_padding: cfg.max_padding,
    };

    let socket = UdpSocket::bind(&cfg.bind_addr).await?;
    println!("[ostp-server] listening on {}", cfg.bind_addr);

    let dispatcher = Dispatcher::new(machine_cfg, access_store.shared());

    let (ui_event_tx, ui_event_rx) = mpsc::unbounded_channel::<UiEvent>();
    let (ui_cmd_tx, ui_cmd_rx) = mpsc::unbounded_channel::<UiCommand>();
    let idle_timeout = Duration::from_secs(cfg.peer_idle_timeout_secs.max(1));
    let initial_keys = access_store.count();

    let mut server_task = tokio::spawn(run_server_loop(
        socket,
        dispatcher,
        cfg.max_datagram_size,
        ui_cmd_rx,
        ui_event_tx.clone(),
        access_store,
    ));

    let mut tui_task = if no_tui {
        None
    } else {
        Some(tokio::spawn(tui::run_server_tui(
            ui_event_rx,
            ui_cmd_tx.clone(),
            initial_keys,
            idle_timeout,
        )))
    };

    let mut signal_task = tokio::spawn(async move {
        wait_for_shutdown_signal().await?;
        let _ = ui_cmd_tx.send(UiCommand::Shutdown);
        Ok::<(), anyhow::Error>(())
    });

    if let Some(tui_task_ref) = &mut tui_task {
        tokio::select! {
            res = &mut server_task => {
                res??;
            }
            res = tui_task_ref => {
                res??;
            }
            res = &mut signal_task => {
                res??;
            }
        }
    } else {
        tokio::select! {
            res = &mut server_task => {
                res??;
            }
            res = &mut signal_task => {
                res??;
            }
        }
    }

    if !server_task.is_finished() {
        server_task.abort();
    }
    if let Some(tui_task) = &mut tui_task {
        if !tui_task.is_finished() {
            tui_task.abort();
        }
    }
    if !signal_task.is_finished() {
        signal_task.abort();
    }

    println!("[ostp-server] shutdown complete");

    Ok(())
}

async fn run_server_loop(
    socket: UdpSocket,
    mut dispatcher: Dispatcher,
    max_datagram_size: usize,
    mut ui_cmd_rx: mpsc::UnboundedReceiver<UiCommand>,
    ui_event_tx: mpsc::UnboundedSender<UiEvent>,
    access_store: AccessKeyStore,
) -> Result<()> {
    let mut buf = vec![0_u8; max_datagram_size.max(512)];
    let mut remotes: HashMap<(u32, u16), TcpStream> = HashMap::new();
    let mut flush_tick = tokio::time::interval(Duration::from_millis(20));
    let _ = ui_event_tx.send(UiEvent::Log("Server loop started".to_string()));
    let _ = ui_event_tx.send(UiEvent::KeyCount(access_store.count()));

    loop {
        tokio::select! {
            cmd = ui_cmd_rx.recv() => {
                match cmd {
                    Some(UiCommand::CreateClientKey) => {
                        let key = access_store.create_new_key()?;
                        let _ = ui_event_tx.send(UiEvent::KeyCreated { key });
                    }
                    Some(UiCommand::Shutdown) | None => {
                        let _ = ui_event_tx.send(UiEvent::Log("Shutdown command received".to_string()));
                        break;
                    }
                }
            }
            received = socket.recv_from(&mut buf) => {
                let (size, peer) = received?;
                let packet = Bytes::copy_from_slice(&buf[..size]);
                match dispatcher.on_datagram(peer, packet) {
                    Ok(DispatchOutcome::Unauthorized) => {
                        let _ = ui_event_tx.send(UiEvent::UnauthorizedProbe { peer: peer.ip(), bytes: size });
                    }
                    Ok(DispatchOutcome::Accepted { response, app_payload, peer_addr }) => {
                        let peer_ip = peer_addr.ip();
                        let _ = ui_event_tx.send(UiEvent::PeerSeen { peer: peer_ip });
                        let _ = ui_event_tx.send(UiEvent::Rx { peer: peer_ip, bytes: size });

                        if let Some(response) = response {
                            let response_len = response.len();
                            let _ = socket.send_to(&response, peer_addr).await?;
                            let _ = ui_event_tx.send(UiEvent::Tx { peer: peer_ip, bytes: response_len });
                        }

                        if let Some((session_id, stream_id, payload)) = app_payload {
                            handle_relay_message(
                                peer_addr,
                                session_id,
                                stream_id,
                                payload,
                                &mut dispatcher,
                                &socket,
                                &mut remotes,
                                &ui_event_tx,
                            ).await?;
                        }
                    }
                    Err(err) => {
                        let _ = ui_event_tx.send(UiEvent::Log(format!("Protocol error for {peer}: {err}")));
                    }
                }
            }
            _ = flush_tick.tick() => {
                flush_remote_reads(&mut dispatcher, &socket, &mut remotes, &ui_event_tx).await?;
            }
        }
    }

    Ok(())
}

async fn handle_relay_message(
    peer_addr: std::net::SocketAddr,
    session_id: u32,
    stream_id: u16,
    payload: Bytes,
    dispatcher: &mut Dispatcher,
    socket: &UdpSocket,
    remotes: &mut HashMap<(u32, u16), TcpStream>,
    ui_event_tx: &mpsc::UnboundedSender<UiEvent>,
) -> Result<()> {
    match RelayMessage::decode(&payload)? {
        RelayMessage::Connect(target) => {
            let _ = ui_event_tx.send(UiEvent::Log(format!("Relay CONNECT from {peer_addr} [{session_id}:{stream_id}] -> {target}")));
            match TcpStream::connect(&target).await {
                Ok(stream) => {
                    remotes.insert((session_id, stream_id), stream);
                    send_relay_to_stream(session_id, stream_id, RelayMessage::ConnectOk, dispatcher, socket, ui_event_tx).await?;
                    let _ = ui_event_tx.send(UiEvent::Log(format!("Relay CONNECT ok for [{session_id}:{stream_id}] -> {target}")));
                }
                Err(err) => {
                    let _ = ui_event_tx.send(UiEvent::Log(format!("Relay CONNECT failed from {peer_addr} [{session_id}:{stream_id}] -> {target}: {err}")));
                    send_relay_to_stream(
                        session_id,
                        stream_id,
                        RelayMessage::Error(format!("connect failed: {err}")),
                        dispatcher,
                        socket,
                        ui_event_tx,
                    )
                    .await?;
                }
            }
        }
        RelayMessage::Data(data) => {
            if let Some(remote) = remotes.get_mut(&(session_id, stream_id)) {
                let _ = remote.write_all(&data).await;
            }
        }
        RelayMessage::KeepAlive => {}
        RelayMessage::Close => {
            remotes.remove(&(session_id, stream_id));
        }
        RelayMessage::ConnectOk => {}
        RelayMessage::Error(msg) => {
            let _ = ui_event_tx.send(UiEvent::Log(format!("Relay error from [{session_id}:{stream_id}]: {msg}")));
        }
    }
    Ok(())
}

async fn flush_remote_reads(
    dispatcher: &mut Dispatcher,
    socket: &UdpSocket,
    remotes: &mut HashMap<(u32, u16), TcpStream>,
    ui_event_tx: &mpsc::UnboundedSender<UiEvent>,
) -> Result<()> {
    let keys: Vec<(u32, u16)> = remotes.keys().copied().collect();
    let mut remove_keys = Vec::new();

    for key in keys {
        let (session_id, stream_id) = key;
        if let Some(remote) = remotes.get_mut(&key) {
            let mut buf = [0_u8; 8192];
            loop {
                match remote.try_read(&mut buf) {
                    Ok(0) => {
                        let _ = send_relay_to_stream(
                            session_id,
                            stream_id,
                            RelayMessage::Close,
                            dispatcher,
                            socket,
                            ui_event_tx,
                        )
                        .await;
                        remove_keys.push(key);
                        break;
                    }
                    Ok(n) => {
                        send_relay_to_stream(
                            session_id,
                            stream_id,
                            RelayMessage::Data(buf[..n].to_vec()),
                            dispatcher,
                            socket,
                            ui_event_tx,
                        )
                        .await?;
                    }
                    Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                        break;
                    }
                    Err(_) => {
                        let _ = send_relay_to_stream(
                            session_id,
                            stream_id,
                            RelayMessage::Close,
                            dispatcher,
                            socket,
                            ui_event_tx,
                        )
                        .await;
                        remove_keys.push(key);
                        break;
                    }
                }
            }
        }
    }

    for key in remove_keys {
        remotes.remove(&key);
    }

    Ok(())
}

async fn send_relay_to_stream(
    session_id: u32,
    stream_id: u16,
    msg: RelayMessage,
    dispatcher: &mut Dispatcher,
    socket: &UdpSocket,
    ui_event_tx: &mpsc::UnboundedSender<UiEvent>,
) -> Result<()> {
    let payload = Bytes::from(msg.encode());
    if let Some((frame, peer_addr)) = dispatcher.outbound_to_session(session_id, stream_id, payload)? {
        let response_len = frame.len();
        let _ = socket.send_to(&frame, peer_addr).await?;
        let _ = ui_event_tx.send(UiEvent::Tx {
            peer: peer_addr.ip(),
            bytes: response_len,
        });
    }
    Ok(())
}
