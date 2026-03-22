use crate::error::AppError;
use crate::state::AppState;
use crate::node_manager::registry::{NodeRegistry, ConnectionType};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tracing::{info, warn, error};

/// Слушает TCP порт и обрабатывает SOCKS5 подключения от B2B клиентов
pub async fn run_socks5_server(addr: std::net::SocketAddr, state: Arc<AppState>) {
    let listener = TcpListener::bind(addr).await.expect("Failed to bind SOCKS5 port");

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
            if let Err(e) = handle_socks_connection(stream, &state).await {
                warn!("SOCKS5 session from {} failed: {}", peer, e);
            }
        });
    }
}

/// Полная обработка SOCKS5 соединения: handshake → auth → connect → relay
async fn handle_socks_connection(mut stream: TcpStream, state: &Arc<AppState>) -> Result<(), AppError> {
    // === 1. SOCKS5 Greeting (RFC 1928) ===
    let mut header = [0u8; 2];
    stream.read_exact(&mut header).await.map_err(|e| AppError::Unexpected(e.into()))?;

    if header[0] != 0x05 {
        return Err(AppError::Unexpected(anyhow::anyhow!("Not a SOCKS5 client")));
    }

    let nmethods = header[1] as usize;
    let mut methods = vec![0u8; nmethods];
    stream.read_exact(&mut methods).await.map_err(|e| AppError::Unexpected(e.into()))?;

    // Требуем username/password auth (0x02)
    if !methods.contains(&0x02) {
        stream.write_all(&[0x05, 0xFF]).await.map_err(|e| AppError::Unexpected(e.into()))?;
        return Err(AppError::Unauthorized);
    }
    stream.write_all(&[0x05, 0x02]).await.map_err(|e| AppError::Unexpected(e.into()))?;

    // === 2. Username/Password Auth (RFC 1929) ===
    // username = фильтр (напр. "US" или "US-wifi"), password = API key
    let mut ver = [0u8; 1];
    stream.read_exact(&mut ver).await.map_err(|e| AppError::Unexpected(e.into()))?;

    let mut ulen = [0u8; 1];
    stream.read_exact(&mut ulen).await.map_err(|e| AppError::Unexpected(e.into()))?;
    let mut username = vec![0u8; ulen[0] as usize];
    stream.read_exact(&mut username).await.map_err(|e| AppError::Unexpected(e.into()))?;

    let mut plen = [0u8; 1];
    stream.read_exact(&mut plen).await.map_err(|e| AppError::Unexpected(e.into()))?;
    let mut password = vec![0u8; plen[0] as usize];
    stream.read_exact(&mut password).await.map_err(|e| AppError::Unexpected(e.into()))?;

    let filter = String::from_utf8_lossy(&username).to_string();
    let api_key = String::from_utf8_lossy(&password).to_string();

    // Аутентификация через Redis → Postgres
    let auth_ctx = match state.authenticator.authenticate(&api_key).await {
        Ok(ctx) => ctx,
        Err(_) => {
            stream.write_all(&[0x01, 0x01]).await.ok();
            return Err(AppError::Unauthorized);
        }
    };
    stream.write_all(&[0x01, 0x00]).await.map_err(|e| AppError::Unexpected(e.into()))?;

    // Парсинг фильтра: "US", "US-wifi", "US-mobile"
    let (country, conn_type) = parse_filter(&filter);

    // === 3. SOCKS5 CONNECT Request ===
    let mut req_header = [0u8; 4];
    stream.read_exact(&mut req_header).await.map_err(|e| AppError::Unexpected(e.into()))?;

    if req_header[1] != 0x01 {
        // Поддерживаем только CONNECT
        stream.write_all(&[0x05, 0x07, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
        return Err(AppError::Unexpected(anyhow::anyhow!("Only CONNECT supported")));
    }

    let target_addr = match req_header[3] {
        0x01 => { // IPv4
            let mut addr = [0u8; 4];
            stream.read_exact(&mut addr).await.map_err(|e| AppError::Unexpected(e.into()))?;
            format!("{}.{}.{}.{}", addr[0], addr[1], addr[2], addr[3])
        }
        0x03 => { // Domain
            let mut dlen = [0u8; 1];
            stream.read_exact(&mut dlen).await.map_err(|e| AppError::Unexpected(e.into()))?;
            let mut domain = vec![0u8; dlen[0] as usize];
            stream.read_exact(&mut domain).await.map_err(|e| AppError::Unexpected(e.into()))?;
            String::from_utf8_lossy(&domain).to_string()
        }
        _ => {
            stream.write_all(&[0x05, 0x08, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
            return Err(AppError::Unexpected(anyhow::anyhow!("Unsupported address type")));
        }
    };

    let mut port_bytes = [0u8; 2];
    stream.read_exact(&mut port_bytes).await.map_err(|e| AppError::Unexpected(e.into()))?;
    let port = u16::from_be_bytes(port_bytes);
    let full_target = format!("{}:{}", target_addr, port);

    // === 4. Выбор ноды и роутинг ===
    let node_id = match state.registry.find_node(country.as_deref(), conn_type).await {
        Ok(id) => id,
        Err(_) => {
            // Host unreachable
            stream.write_all(&[0x05, 0x04, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
            return Err(AppError::NodeOffline);
        }
    };

    // Проверяем баланс (10MB минимум)
    let billing = crate::billing::engine::DefaultBillingEngine {
        db_pool: state.db_pool.clone(),
        redis_client: state.redis_client.clone(),
        price_per_gb_usd: state.price_per_gb_usd,
    };
    
    use crate::billing::BillingEngine;
    if let Err(_) = billing.reserve_balance(auth_ctx.client_id, 10_485_760).await {
        stream.write_all(&[0x05, 0x02, 0x00, 0x01, 0,0,0,0, 0,0]).await.ok();
        return Err(AppError::InsufficientBalance);
    }

    // SOCKS5 success response
    stream.write_all(&[0x05, 0x00, 0x00, 0x01, 0,0,0,0, 0,0]).await
        .map_err(|e| AppError::Unexpected(e.into()))?;

    info!("SOCKS5 CONNECT {} → node {} for client {}", full_target, node_id, auth_ctx.client_id);

    // === 5. Relay через WS-туннель ===
    let bytes = super::router::route_stream(state, stream, &full_target, node_id).await?;

    // === 6. Биллинг ===
    billing.commit_usage(auth_ctx.client_id, node_id, bytes).await?;

    Ok(())
}

/// Парсит фильтр из SOCKS5 username: "US", "US-wifi", "DE-mobile"
fn parse_filter(filter: &str) -> (Option<String>, Option<ConnectionType>) {
    let parts: Vec<&str> = filter.splitn(2, '-').collect();
    let country = if parts[0].is_empty() { None } else { Some(parts[0].to_uppercase()) };
    let conn_type = parts.get(1).and_then(|t| {
        match t.to_lowercase().as_str() {
            "wifi" => Some(ConnectionType::WiFi),
            "mobile" => Some(ConnectionType::Mobile),
            _ => None,
        }
    });
    (country, conn_type)
}
