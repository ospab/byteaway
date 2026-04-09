use crate::error::AppError;
use crate::state::AppState;
use crate::node_manager::registry::{NodeRegistry, ConnectionType};
use redis::AsyncCommands;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{sleep, Duration};
use tracing::{info, warn, error};
use uuid::Uuid;

/// Слушает TCP порт и обрабатывает SOCKS5 подключения от B2B клиентов
pub async fn run_socks5_server(listener: TcpListener, state: Arc<AppState>) {
    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(v) => v,
            Err(e) => {
                error!("SOCKS5 accept error: {}", e);
                continue;
            }
        };

        let state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_socks_connection(stream, &state, peer).await {
                warn!("SOCKS5 session from {} failed: {}", peer, e);
            }
        });
    }
}

/// Полная обработка SOCKS5 соединения: handshake → auth → connect → relay
async fn handle_socks_connection(mut stream: TcpStream, state: &Arc<AppState>, peer_addr: std::net::SocketAddr) -> Result<(), AppError> {
    use tokio::io::BufReader;
    let mut reader = BufReader::with_capacity(1024, &mut stream);

    // === 1. SOCKS5 Greeting (RFC 1928) ===
    let mut header = [0u8; 2];
    reader.read_exact(&mut header).await.map_err(|e| AppError::Unexpected(e.into()))?;

    if header[0] != 0x05 {
        return Err(AppError::Unexpected(anyhow::anyhow!("Not a SOCKS5 client")));
    }

    let nmethods = header[1] as usize;
    let mut methods = vec![0u8; nmethods];
    reader.read_exact(&mut methods).await.map_err(|e| AppError::Unexpected(e.into()))?;

    // Требуем username/password auth (0x02)
    if !methods.contains(&0x02) {
        reader.get_mut().write_all(&[0x05, 0xFF]).await.map_err(|e| AppError::Unexpected(e.into()))?;
        return Err(AppError::Unauthorized);
    }
    reader.get_mut().write_all(&[0x05, 0x02]).await.map_err(|e| AppError::Unexpected(e.into()))?;

    // === 2. Username/Password Auth (RFC 1929) ===
    let mut ver = [0u8; 1];
    reader.read_exact(&mut ver).await.map_err(|e| AppError::Unexpected(e.into()))?;

    let mut ulen = [0u8; 1];
    reader.read_exact(&mut ulen).await.map_err(|e| AppError::Unexpected(e.into()))?;
    let mut username = vec![0u8; ulen[0] as usize];
    reader.read_exact(&mut username).await.map_err(|e| AppError::Unexpected(e.into()))?;

    let mut plen = [0u8; 1];
    reader.read_exact(&mut plen).await.map_err(|e| AppError::Unexpected(e.into()))?;
    let mut password = vec![0u8; plen[0] as usize];
    reader.read_exact(&mut password).await.map_err(|e| AppError::Unexpected(e.into()))?;


    let filter = String::from_utf8_lossy(&username).trim().trim_matches('\0').to_string();
    let api_key = String::from_utf8_lossy(&password).trim().trim_matches('\0').to_string();

    // Аутентификация через Redis → Postgres с защитой от брутфорса
    let auth_ctx = match state.authenticator.authenticate(&api_key, &peer_addr.ip().to_string()).await {
        Ok(ctx) => ctx,
        Err(_) => {
            reader.get_mut().write_all(&[0x01, 0x01]).await.ok();
            return Err(AppError::Unauthorized);
        }
    };
    reader.get_mut().write_all(&[0x01, 0x00]).await.map_err(|e| AppError::Unexpected(e.into()))?;

    // Парсинг фильтра: "US", "US-wifi", "US-mobile"
    let (country, conn_type) = parse_filter(&filter);

    // === 3. SOCKS5 CONNECT Request ===
    let mut req_header = [0u8; 4];
    reader.read_exact(&mut req_header).await.map_err(|e| AppError::Unexpected(e.into()))?;

    if req_header[1] != 0x01 {
        // Поддерживаем только CONNECT
        reader.get_mut().write_all(&[0x05, 0x07, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
        return Err(AppError::Unexpected(anyhow::anyhow!("Only CONNECT supported")));
    }

    let target_addr = match req_header[3] {
        0x01 => { // IPv4
            let mut addr = [0u8; 4];
            reader.read_exact(&mut addr).await.map_err(|e| AppError::Unexpected(e.into()))?;
            format!("{}.{}.{}.{}", addr[0], addr[1], addr[2], addr[3])
        }
        0x03 => { // Domain
            let mut dlen = [0u8; 1];
            reader.read_exact(&mut dlen).await.map_err(|e| AppError::Unexpected(e.into()))?;
            let mut domain = vec![0u8; dlen[0] as usize];
            reader.read_exact(&mut domain).await.map_err(|e| AppError::Unexpected(e.into()))?;
            String::from_utf8_lossy(&domain).to_string()
        }
        _ => {
            reader.get_mut().write_all(&[0x05, 0x08, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
            return Err(AppError::Unexpected(anyhow::anyhow!("Unsupported address type")));
        }
    };

    let mut port_bytes = [0u8; 2];
    reader.read_exact(&mut port_bytes).await.map_err(|e| AppError::Unexpected(e.into()))?;
    let port = u16::from_be_bytes(port_bytes);
    let full_target = format!("{}:{}", target_addr, port);


    // === 4. Выбор ноды и роутинг ===
    let node_result = choose_node_for_client_with_retry(
        state,
        auth_ctx.client_id,
        country.as_deref(),
        conn_type,
    )
    .await;
    
    // Проверяем баланс (10MB минимум)
    let billing = crate::billing::engine::DefaultBillingEngine {
        db_pool: state.db_pool.clone(),
        redis_client: state.redis_client.clone(),
        price_per_gb_usd: state.price_per_gb_usd,
    };
    use crate::billing::BillingEngine;

    match node_result {
        Ok(node_id) => {
            if let Err(_) = billing.reserve_balance(auth_ctx.client_id, 10_485_760).await {
                reader.get_mut().write_all(&[0x05, 0x02, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
                return Err(AppError::InsufficientBalance);
            }

            // SOCKS5 success response
            reader.get_mut().write_all(&[0x05, 0x00, 0x00, 0x01, 0,0,0,0, 0,0]).await
                .map_err(|e| AppError::Unexpected(e.into()))?;

            info!("SOCKS5 CONNECT {} → node {} for client {}", full_target, node_id, auth_ctx.client_id);

            // Собираем то, что могло остаться в буфере Reader-а (начальные данные от клиента)
            let initial_data = reader.buffer().to_vec();

            // Relay через WS-туннель (учет трафика теперь внутри route_stream)
            super::router::route_stream(state, stream, &full_target, node_id, auth_ctx.client_id, initial_data).await?;
        }
        Err(_) => {
            // NO NODES AVAILABLE: Отклоняем соединение
            state.failed_node_selections.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            warn!("SOCKS5 REJECTED: No mobile nodes available for filter '{}' for client {}", filter, auth_ctx.client_id);
            
            // SOCKS5 error response: 0x03 (Network unreachable) или 0x04 (Host unreachable)
            reader.get_mut().write_all(&[0x05, 0x03, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
            return Err(AppError::NodeOffline);
        }
    }



    Ok(())
}

async fn choose_node_for_client(
    state: &Arc<AppState>,
    client_id: Uuid,
    country: Option<&str>,
    conn_type: Option<ConnectionType>,
) -> Result<Uuid, AppError> {
    let country_key = country.unwrap_or("ANY").to_uppercase();
    let sticky_key = format!("proxy:sticky-node:{}:{}", client_id, country_key);

    // 1) Try sticky assignment first.
    if let Ok(mut conn) = state.redis_client.get_multiplexed_async_connection().await {
        let cached_node: Option<String> = conn.get(&sticky_key).await.ok();
        if let Some(raw) = cached_node {
            if let Ok(node_id) = Uuid::parse_str(raw.trim()) {
                if state.registry.active_connections.contains_key(&node_id) {
                    info!(
                        "Node select sticky hit client={} country={} node={}",
                        client_id,
                        country_key,
                        node_id
                    );
                    return Ok(node_id);
                }
                info!(
                    "Node select sticky stale client={} country={} node={}",
                    client_id,
                    country_key,
                    node_id
                );
            }
        }
    }

    // 2) Fallback to normal selection.
    let node_id = state.registry.find_node(country, conn_type).await?;
    info!(
        "Node select fresh client={} country={} node={}",
        client_id,
        country_key,
        node_id
    );

    // 3) Save sticky assignment with TTL to keep flow stable for multi-request tests.
    if let Ok(mut conn) = state.redis_client.get_multiplexed_async_connection().await {
        let _: Result<(), _> = conn.set_ex(&sticky_key, node_id.to_string(), 300).await;
    }

    Ok(node_id)
}

async fn choose_node_for_client_with_retry(
    state: &Arc<AppState>,
    client_id: Uuid,
    country: Option<&str>,
    conn_type: Option<ConnectionType>,
) -> Result<Uuid, AppError> {
    // Give nodes a short grace window to reconnect/register.
    let mut last_err: Option<AppError> = None;
    for attempt in 1..=6 {
        match choose_node_for_client(state, client_id, country, conn_type.clone()).await {
            Ok(id) => {
                if attempt > 1 {
                    info!("Node select recovered on attempt {} for client={} node={}", attempt, client_id, id);
                }
                return Ok(id);
            }
            Err(e) => {
                warn!("Node select attempt {} failed for client={}: {}", attempt, client_id, e);
                last_err = Some(e);
                if attempt < 6 {
                    sleep(Duration::from_secs(2)).await;
                }
            }
        }
    }
    Err(last_err.unwrap_or(AppError::NodeOffline))
}

/// Парсит фильтр из SOCKS5 username: "US", "US-wifi", "DE-mobile"
fn parse_filter(filter: &str) -> (Option<String>, Option<ConnectionType>) {
    let cleaned = filter.trim();
    let parts: Vec<&str> = cleaned.split('-').collect();

    let country = parts
        .first()
        .and_then(|c| {
            let c = c.trim();
            if c.is_empty() { None } else { Some(c.to_uppercase()) }
        });

    let conn_type = parts.get(1).and_then(|t| {
        match t.trim().to_lowercase().as_str() {
            "wifi" => Some(ConnectionType::WiFi),
            "mobile" => Some(ConnectionType::Mobile),
            _ => None,
        }
    });
    (country, conn_type)
}
