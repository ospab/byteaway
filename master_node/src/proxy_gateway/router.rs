use crate::error::AppError;
use crate::state::AppState;
use crate::node_manager::registry::WsCommand;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::mpsc;
use tracing::info;
use uuid::Uuid;

/// Роутит один SOCKS5-стрим через мобильную ноду по WS-туннелю.
/// Возвращает общее количество переданных байт (upload + download).
pub async fn route_stream(
    state: &Arc<AppState>,
    client_stream: tokio::net::TcpStream,
    target_addr: &str,
    node_id: Uuid,
) -> Result<u64, AppError> {
    let session_id = Uuid::new_v4();

    // Канал для получения данных ОТ мобильной ноды
    let (reply_tx, mut reply_rx) = mpsc::channel::<Vec<u8>>(1024);

    // Получаем mpsc::Sender<WsCommand> для нужной ноды
    let entry = state.registry.active_connections
        .get(&node_id)
        .ok_or(AppError::NodeOffline)?;

    let node_tx = entry.tx.clone();
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

    let node_tx_data = node_tx.clone();
    let sid = session_id;

    // TCP → WS (upload: данные от SOCKS5 клиента к мобильной ноде)
    let upload = tokio::spawn(async move {
        let mut buf = vec![0u8; 65536];
        let mut total = 0u64;
        loop {
            let n = match tcp_reader.read(&mut buf).await {
                Ok(0) | Err(_) => break,
                Ok(n) => n,
            };
            total += n as u64;
            if node_tx_data.send(WsCommand::Data {
                session_id: sid,
                payload: buf[..n].to_vec(),
            }).await.is_err() {
                break;
            }
        }
        total
    });

    // WS → TCP (download: данные от мобильной ноды к SOCKS5 клиенту)
    let download = tokio::spawn(async move {
        let mut total = 0u64;
        while let Some(data) = reply_rx.recv().await {
            total += data.len() as u64;
            if tcp_writer.write_all(&data).await.is_err() {
                break;
            }
        }
        total
    });

    let (up, down) = tokio::join!(upload, download);
    let total_bytes = up.unwrap_or(0) + down.unwrap_or(0);

    // 3. Закрываем сессию
    let _ = node_tx.send(WsCommand::Close { session_id }).await;

    // Декрементируем счётчик сессий
    if let Some(entry) = state.registry.active_connections.get(&node_id) {
        entry.active_sessions.fetch_sub(1, Ordering::Relaxed);
    }

    info!("Session {} routed {} bytes through node {}", session_id, total_bytes, node_id);
    Ok(total_bytes)
}
