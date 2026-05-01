use crate::node_manager::registry::NodeRegistry;
use crate::error::AppError;
use crate::state::AppState;
use crate::node_manager::registry::TunnelCommand;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::mpsc;
use tracing::{info, warn};
use uuid::Uuid;

/// Роутит один SOCKS5-стрим через мобильную ноду по WS-туннелю.
/// Возвращает общее количество переданных байт (upload + download).
pub async fn route_stream(
    state: &Arc<AppState>,
    client_stream: tokio::net::TcpStream,
    target_addr: &str,
    node_id: Uuid,
    client_id: Uuid,
    initial_data: Vec<u8>,
) -> Result<u64, AppError> {

    let session_id = Uuid::new_v4();
    info!(
        "route_stream start sid={} client={} node={} target={} initial={}B",
        session_id,
        client_id,
        node_id,
        target_addr,
        initial_data.len()
    );

    // Канал для получения данных ОТ мобильной ноды
    let (reply_tx, mut reply_rx) = mpsc::channel::<Vec<u8>>(128);

    // Получаем mpsc::Sender<TunnelCommand> для нужной ноды
    let entry = NodeRegistry::active_connections(&*state.registry)
        .get(&node_id)
        .ok_or(AppError::NodeOffline)?;

    let node_tx: mpsc::Sender<TunnelCommand> = entry.tx.clone();

    entry.active_sessions.fetch_add(1, Ordering::Relaxed);
    drop(entry);

    // 1. Отправляем команду OPEN в WS-хендлер
    let send_result: Result<(), mpsc::error::SendError<TunnelCommand>> = node_tx.send(TunnelCommand::Open {
        session_id,
        target_addr: target_addr.to_string(),
        reply_tx,
    }).await;
    send_result.map_err(|_| AppError::NodeOffline)?;

    // 2. Двунаправленный relay: TCP ↔ WS
    let (mut tcp_reader, mut tcp_writer) = client_stream.into_split();

    let node_tx_data: mpsc::Sender<TunnelCommand> = node_tx.clone();
    let sid = session_id;


    // TCP → WS (upload: данные от SOCKS5 клиента к мобильной ноде)
    let state_up = state.clone();
    let mut upload = tokio::spawn(async move {
        let mut buf = vec![0u8; 16384];
        let mut total = 0u64;
        let mut interim = 0u64;

        // Отправляем начальные данные (те, что застряли в BufReader при SOCKS5 handshake)
        if !initial_data.is_empty() {
            total += initial_data.len() as u64;
            interim += initial_data.len() as u64;
            let send_result: Result<(), mpsc::error::SendError<TunnelCommand>> = node_tx_data.send(TunnelCommand::Data {
                session_id: sid,
                payload: initial_data,
            }).await;
            if send_result.is_err() {
                return 0;
            }
        }

        loop {
            let n = match tcp_reader.read(&mut buf).await {
                Ok(0) => {
                    info!("[{}] TCP read closed (EOF), total={}B", &sid.to_string()[..8], total);
                    break;
                }
                Ok(n) => n,
                Err(e) => {
                    info!("[{}] TCP read error: {:?}, total={}B", &sid.to_string()[..8], e, total);
                    break;
                }
            };
            total += n as u64;
            interim += n as u64;

            // Interim billing every 1MB (spawn to avoid blocking relay)
            if interim >= 1_048_576 {
                let state_clone = state_up.clone();
                let client_id_clone = client_id;
                let node_id_clone = node_id;
                let interim_val = interim;
                tokio::spawn(async move {
                    let _ = state_clone.billing_engine.commit_usage(client_id_clone, node_id_clone, interim_val).await;
                });
                interim = 0;
            }


            let send_result: Result<(), mpsc::error::SendError<TunnelCommand>> = node_tx_data.send(TunnelCommand::Data {
                session_id: sid,
                payload: buf[..n].to_vec(),
            }).await;
            if send_result.is_err() {
                warn!("[{}] WS send failed, breaking", &sid.to_string()[..8]);
                break;
            }
            info!("[{}] → sent {} bytes to node", &sid.to_string()[..8], n);
        }
        // Commit remaining
        if interim > 0 {
            let _ = state_up.billing_engine.commit_usage(client_id, node_id, interim).await;
        }
        total
    });

    // WS → TCP (download: данные от мобильной ноды к SOCKS5 клиенту)
    let state_down = state.clone();
    let mut download = tokio::spawn(async move {
        let mut total = 0u64;
        let mut interim = 0u64;
        while let Some(data) = reply_rx.recv().await {
            total += data.len() as u64;
            interim += data.len() as u64;
            info!("[{}] ← received {} bytes from node, total={}B", &sid.to_string()[..8], data.len(), total);

            // Interim billing every 1MB
            if interim >= 1_048_576 {
                let _ = state_down.billing_engine.commit_usage(client_id, node_id, interim).await;
                interim = 0;
            }

            if tcp_writer.write_all(&data).await.is_err() {
                warn!("[{}] TCP write failed, breaking", &sid.to_string()[..8]);
                break;
            }
            tcp_writer.flush().await.ok();
            info!("[{}] → wrote {} bytes to client", &sid.to_string()[..8], data.len());
        }
        info!("[{}] Download loop ended, total={}B", &sid.to_string()[..8], total);
        // Commit remaining
        if interim > 0 {
            let _ = state_down.billing_engine.commit_usage(client_id, node_id, interim).await;
        }
        total
    });


    let (upload_bytes, download_bytes) = tokio::select! {
        up = &mut upload => {
            let up_bytes = up.unwrap_or(0);
            
            // Client disconnected. Tell the node to close its end IMMEDIATELY
            // to avoid hanging the session for 120s.
            let _ = node_tx.send(TunnelCommand::Close { session_id }).await;
            
            // Still give a short window for any remaining data from the node (e.g. final HTTP body bytes)
            let down_bytes = match tokio::time::timeout(std::time::Duration::from_secs(5), &mut download).await {
                Ok(v) => v.unwrap_or(0),
                Err(_) => {
                    download.abort();
                    let _ = download.await;
                    0
                }
            };
            (up_bytes, down_bytes)
        }
        down = &mut download => {
            let down_bytes = down.unwrap_or(0);
            // Node disconnected or closed the session.
            upload.abort();
            let _ = upload.await;
            (0, down_bytes)
        }
    };

    let total_bytes = upload_bytes + download_bytes;

    // 3. Final cleanup ensure (idempotent)
    let _ = node_tx.send(TunnelCommand::Close { session_id }).await;

    if let Some(entry) = NodeRegistry::active_connections(&*state.registry).get(&node_id) {
        entry.active_sessions.fetch_sub(1, Ordering::Relaxed);
    }

    info!(
        "Session {} routed total={}B (up={}B down={}B) through node {}",
        session_id,
        total_bytes,
        upload_bytes,
        download_bytes,
        node_id
    );
    Ok(total_bytes)
}
