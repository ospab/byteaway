use crate::error::AppError;
use crate::state::AppState;
use crate::node_manager::registry::WsCommand;
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
    let (reply_tx, mut reply_rx) = mpsc::channel::<Vec<u8>>(1024);

    // Получаем mpsc::Sender<WsCommand> для нужной ноды
    let entry = state.registry.active_connections
        .get(&node_id)
        .ok_or(AppError::NodeOffline)?;

    let node_tx: mpsc::Sender<WsCommand> = entry.tx.clone();

    entry.active_sessions.fetch_add(1, Ordering::Relaxed);
    drop(entry);

    // 1. Отправляем команду OPEN в WS-хендлер
    node_tx.send(WsCommand::Open {
        session_id,
        target_addr: target_addr.to_string(),
        reply_tx,
    })
    .await
    .map_err(|_| AppError::NodeOffline)?;

    // 2. Двунаправленный relay: TCP ↔ WS
    let (mut tcp_reader, mut tcp_writer) = client_stream.into_split();

    let node_tx_data: mpsc::Sender<WsCommand> = node_tx.clone();
    let sid = session_id;


    // TCP → WS (upload: данные от SOCKS5 клиента к мобильной ноде)
    let state_up = state.clone();
    let mut upload = tokio::spawn(async move {
        let mut buf = vec![0u8; 65536];
        let mut total = 0u64;
        let mut interim = 0u64;

        // Отправляем начальные данные (те, что застряли в BufReader при SOCKS5 handshake)
        if !initial_data.is_empty() {
            total += initial_data.len() as u64;
            interim += initial_data.len() as u64;
            if node_tx_data.send(WsCommand::Data {
                session_id: sid,
                payload: initial_data,
            }).await.is_err() {
                return 0;
            }
        }

        loop {
            let n = match tcp_reader.read(&mut buf).await {
                Ok(0) | Err(_) => break,
                Ok(n) => n,
            };
            total += n as u64;
            interim += n as u64;

            // Interim billing every 1MB
            if interim >= 1_048_576 {
                let _ = state_up.billing_engine.commit_usage(client_id, node_id, interim).await;
                interim = 0;
            }


            if node_tx_data.send(WsCommand::Data {
                session_id: sid,
                payload: buf[..n].to_vec(),
            }).await.is_err() {
                break;
            }
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

            // Interim billing every 1MB
            if interim >= 1_048_576 {
                let _ = state_down.billing_engine.commit_usage(client_id, node_id, interim).await;
                interim = 0;
            }

            if tcp_writer.write_all(&data).await.is_err() {
                break;
            }
        }
        // Commit remaining
        if interim > 0 {
            let _ = state_down.billing_engine.commit_usage(client_id, node_id, interim).await;
        }
        total
    });


    // Keep both directions alive long enough for response bodies.
    // If upload finishes first (common for HTTP GET), we still wait for download.
    // If download finishes first, we can abort upload.
    let (upload_bytes, download_bytes) = tokio::select! {
        up = &mut upload => {
            let up_bytes = up.unwrap_or(0);
            let down_bytes = match tokio::time::timeout(std::time::Duration::from_secs(120), &mut download).await {
                Ok(v) => v.unwrap_or(0),
                Err(_) => {
                    warn!(
                        "route_stream download timeout after upload sid={} client={} node={} waited=120s up={}B",
                        session_id,
                        client_id,
                        node_id,
                        up_bytes
                    );
                    download.abort();
                    0
                }
            };
            info!(
                "route_stream upload completed sid={} client={} node={} up={}B down={}B",
                session_id,
                client_id,
                node_id,
                up_bytes,
                down_bytes
            );
            (up_bytes, down_bytes)
        }
        down = &mut download => {
            let down_bytes = down.unwrap_or(0);
            info!(
                "route_stream download completed sid={} client={} node={} down={}B",
                session_id,
                client_id,
                node_id,
                down_bytes
            );

            // Do not abort upload immediately: many HTTPS clients may still be
            // about to send first TLS bytes while downstream already closed.
            // Give upload a short grace window before force-abort.
            let up_bytes = match tokio::time::timeout(std::time::Duration::from_secs(20), &mut upload).await {
                Ok(v) => v.unwrap_or(0),
                Err(_) => {
                    warn!(
                        "route_stream upload grace timeout after download sid={} client={} node={} waited=20s down={}B",
                        session_id,
                        client_id,
                        node_id,
                        down_bytes
                    );
                    upload.abort();
                    let _ = upload.await;
                    0
                }
            };

            info!(
                "route_stream upload finalized after download sid={} client={} node={} up={}B",
                session_id,
                client_id,
                node_id,
                up_bytes
            );
            (up_bytes, down_bytes)
        }
    };

    let total_bytes = upload_bytes + download_bytes;

    // 3. Закрываем сессию
    let _ = node_tx.send(WsCommand::Close { session_id }).await;

    // Декрементируем счётчик сессий
    if let Some(entry) = state.registry.active_connections.get(&node_id) {
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
