use axum::{extract::{State, Query}, Extension, Json};
use crate::auth::AuthContext;
use crate::error::AppError;
use crate::state::AppState;
use chrono::{Duration, Utc};
use redis::AsyncCommands;
use serde::{Serialize, Deserialize};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::sync::Arc;
use tracing::info;

const FREE_DAILY_LIMIT_BYTES: i64 = 1_073_741_824;

fn is_paid_tier(balance: f64, reward_unlimited_until: Option<chrono::DateTime<Utc>>, node_active: bool) -> bool {
    let has_reward_unlimited = reward_unlimited_until
        .map(|until| until > Utc::now())
        .unwrap_or(false);
    balance >= 1.0 || has_reward_unlimited || node_active
}

#[derive(Serialize)]
pub struct TrafficStatsResponse {
    pub records: Vec<TrafficRecordResponse>,
}

#[derive(Serialize, sqlx::FromRow)]
pub struct TrafficRecordResponse {
    pub date: String,
    pub bytes_shared: i64,
    pub bytes_consumed: i64,
    pub earned_usd: f64,
}

#[derive(Deserialize)]
pub struct StatsQuery {
    pub days: Option<i32>,
}

#[derive(Serialize)]
pub struct BalanceResponse {
    pub client_id: String,
    pub balance_usd: f64,
    pub vpn_days_remaining: i32,
    pub vpn_seconds_remaining: i64,
    pub vpn_pending_days: i32,
    pub tier: String,
    pub free_daily_limit_bytes: i64,
    pub free_daily_used_bytes: i64,
    pub free_daily_remaining_bytes: i64,
}

#[derive(serde::Deserialize)]
pub struct RegisterNodeRequest {
    pub device_id: String,
}

#[derive(Serialize)]
pub struct RegisterNodeResponse {
    pub node_id: uuid::Uuid,
    pub token: String,
}

/// POST /api/v1/auth/register-node — Регистрация B2C ноды по Device ID
pub async fn register_node(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterNodeRequest>,
) -> Result<Json<RegisterNodeResponse>, AppError> {
    if payload.device_id.trim().is_empty() {
        return Err(AppError::Unauthorized);
    }

    // Stable UUID derived from HWID/device_id to keep balance tied to one device identity.
    let digest = Sha256::digest(payload.device_id.trim().as_bytes());
    let mut raw = [0u8; 16];
    raw.copy_from_slice(&digest[..16]);
    // Mark as RFC4122 variant + v5-like version bits for consistency.
    raw[6] = (raw[6] & 0x0f) | 0x50;
    raw[8] = (raw[8] & 0x3f) | 0x80;
    let device_uuid = uuid::Uuid::from_bytes(raw);

    // Используем транзакцию, чтобы создать и ноду, и клиента (чтобы баланс работал)
    let mut tx = state.db_pool.begin().await.map_err(AppError::Database)?;

    let node_id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO mobile_nodes (id, device_id) \
         VALUES ($1, $2) \
         ON CONFLICT (device_id) DO UPDATE SET registered_at = NOW() \
         RETURNING id",
    )
    .bind(device_uuid)
    .bind(&payload.device_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(AppError::Database)?;

    sqlx::query(
        "INSERT INTO clients (id, email, balance_usd) \
         VALUES ($1, $2, 0.0) \
         ON CONFLICT DO NOTHING"
    )
    .bind(node_id)
    .bind(format!("{}@byteaway.internal", payload.device_id))
    .execute(&mut *tx)
    .await
    .map_err(AppError::Database)?;

    tx.commit().await.map_err(AppError::Database)?;

    // В продакшене тут должен генерироваться JWT.
    // Пока используем node_id как токен для простоты, но это уже реальный UUID.
    Ok(Json(RegisterNodeResponse {
        node_id,
        token: node_id.to_string(),
    }))
}

/// GET /api/v1/balance — баланс текущего клиента (по API ключу)
pub async fn get_balance(
    State(state): State<Arc<AppState>>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<BalanceResponse>, AppError> {
    // Пытаемся плавно найти баланс. Если клиента нет (старый переходный период), создаем его.
    let (balance, pending_days, unlimited_until): (f64, i32, Option<chrono::DateTime<Utc>>) = match sqlx::query(
        "SELECT
            balance_usd::float8 as balance,
            COALESCE(reward_pending_days, 0) as reward_pending_days,
            reward_unlimited_until
         FROM clients
         WHERE id = $1"
    )
    .bind(auth.client_id)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(AppError::Database)?
    {
        Some(r) => (r.get("balance"), r.get("reward_pending_days"), r.get("reward_unlimited_until")),
        None => {
            // Если не нашли в clients, проверяем в mobile_nodes
            let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM mobile_nodes WHERE id = $1)")
                .bind(auth.client_id)
                .fetch_one(&state.db_pool)
                .await
                .map_err(AppError::Database)?;

            if exists {
                // Автоматически чиним: создаем клиента для этой ноды
                sqlx::query("INSERT INTO clients (id, email, balance_usd) VALUES ($1, $2, 0.0) ON CONFLICT DO NOTHING")
                    .bind(auth.client_id)
                    .bind(format!("{}@byteaway.internal", auth.client_id))
                    .execute(&state.db_pool)
                    .await
                    .map_err(AppError::Database)?;
                (0.0, 0, None)
            } else {
                return Err(AppError::Unauthorized);
            }
        }
    };

    let now = Utc::now();
    let vpn_seconds_remaining = unlimited_until
        .filter(|ts| *ts > now)
        .map(|ts| (ts - now).num_seconds())
        .unwrap_or(0)
        .max(0);

    // This reflects only active unlimited time.
    let vpn_days_remaining = ((vpn_seconds_remaining as f64) / 86_400.0).ceil() as i32;
    let vpn_pending_days = pending_days.max(0);
    let node_active = state.registry.active_connections.contains_key(&auth.client_id);
    let paid = is_paid_tier(balance, unlimited_until, node_active);

    let used_today: i64 = sqlx::query_scalar(
        "SELECT COALESCE(bytes_used, 0) FROM client_daily_traffic WHERE client_id = $1 AND traffic_date = CURRENT_DATE"
    )
    .bind(auth.client_id)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(AppError::Database)?
    .unwrap_or(0);

    let free_daily_limit_bytes = FREE_DAILY_LIMIT_BYTES;
    let free_daily_used_bytes = if paid { 0 } else { used_today.max(0) };
    let free_daily_remaining_bytes = if paid {
        0
    } else {
        (free_daily_limit_bytes - free_daily_used_bytes).max(0)
    };
    let tier = if paid { "paid" } else { "free" }.to_string();

    Ok(Json(BalanceResponse {
        client_id: auth.client_id.to_string(),
        balance_usd: balance,
        vpn_days_remaining,
        vpn_seconds_remaining,
        vpn_pending_days,
        tier,
        free_daily_limit_bytes,
        free_daily_used_bytes,
        free_daily_remaining_bytes,
    }))
}

#[derive(Serialize)]
pub struct ProxyListResponse {
    pub active_nodes: usize,
    pub countries: Vec<CountryInfo>,
}

#[derive(Serialize)]
pub struct CountryInfo {
    pub code: String,
    pub nodes: usize,
}

/// GET /api/v1/proxies — список доступных стран и количество нод
pub async fn get_proxies(
    State(state): State<Arc<AppState>>,
) -> Result<Json<ProxyListResponse>, AppError> {
    let mut conn = state.redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let keys: Vec<String> = redis::cmd("KEYS")
        .arg("nodes:by_country:*")
        .query_async(&mut conn)
        .await
        .map_err(AppError::Redis)?;

    let mut countries = Vec::new();
    let mut total = 0usize;

    for key in &keys {
        let code = key.strip_prefix("nodes:by_country:").unwrap_or_default().to_string();
        let count: usize = conn.scard(key).await.map_err(AppError::Redis)?;
        total += count;
        countries.push(CountryInfo { code, nodes: count });
    }

    Ok(Json(ProxyListResponse {
        active_nodes: total,
        countries,
    }))
}

/// GET /api/v1/stats — агрегированная статистика по дням
pub async fn get_stats(
    State(state): State<Arc<AppState>>,
    Extension(auth): Extension<AuthContext>,
    Query(params): Query<StatsQuery>,
) -> Result<Json<TrafficStatsResponse>, AppError> {
    let days = params.days.unwrap_or(30);

    // Агрегируем потребление (consumed) и выдачу (shared) по дням.
    // client_id = auth.client_id (пользователь качал трафик)
    // node_id = auth.client_id (пользователь шарил трафик)
    let records = sqlx::query_as::<_, TrafficRecordResponse>(
        "SELECT \
            COALESCE(c.day, s.day)::text as date, \
            COALESCE(s.shared, 0)::bigint as bytes_shared, \
            COALESCE(c.consumed, 0)::bigint as bytes_consumed, \
            COALESCE(s.earned, 0.0)::float8 as earned_usd \
         FROM ( \
            SELECT period_start::date as day, SUM(bytes_used) as consumed \
            FROM traffic_history \
            WHERE client_id = $1 \
            GROUP BY 1 \
         ) c \
         FULL OUTER JOIN ( \
            SELECT period_start::date as day, SUM(bytes_used) as shared, SUM(billed_usd) * 0.7 as earned \
            FROM traffic_history \
            WHERE node_id = $1 \
            GROUP BY 1 \
         ) s ON c.day = s.day \
         WHERE COALESCE(c.day, s.day) > CURRENT_DATE - ($2 * INTERVAL '1 day') \
         ORDER BY 1 DESC"
    )
    .bind(auth.client_id)
    .bind(days)
    .fetch_all(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    Ok(Json(TrafficStatsResponse { records }))
}

/// GET /api/v1/vpn/config — ссылка для VPN (VLESS+Reality)
#[derive(Serialize)]
pub struct VpnConfigResponse {
    pub vless_link: String,
    pub core_config_json: String,
    pub assigned_ip: String,
    pub subnet: String,
    pub gateway: String,
    pub dns: Vec<String>,
    pub tier: String,
    pub max_speed_mbps: i32,
    pub free_daily_limit_bytes: i64,
    pub free_daily_used_bytes: i64,
    pub free_daily_remaining_bytes: i64,
    pub node_active: bool,
}

#[derive(Deserialize)]
pub struct VpnConfigQuery {
}

pub async fn get_vpn_config(
    State(state): State<Arc<AppState>>,
    Query(_query): Query<VpnConfigQuery>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<VpnConfigResponse>, AppError> {
    // Parse Reality destination (host:port), fall back to default if malformed
    let reality_dest = state.reality_dest.as_str();
    let (reality_host, _reality_port) = reality_dest
        .split_once(':')
        .map(|(host, port)| (host.to_string(), port.parse::<u16>().unwrap_or(443)))
        .unwrap_or_else(|| (reality_dest.to_string(), 443));

    // 1. Get client balance (free tier allowed with $0)
    let mut tx = state.db_pool.begin().await.map_err(AppError::Database)?;

    let row = sqlx::query(
        "SELECT
            balance_usd::float8 as balance,
            COALESCE(reward_pending_days, 0) as reward_pending_days,
            reward_unlimited_until
         FROM clients
         WHERE id = $1
         FOR UPDATE"
    )
        .bind(auth.client_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(AppError::Database)?;

    let (balance, pending_days, mut reward_unlimited_until): (f64, i32, Option<chrono::DateTime<Utc>>) = match row {
        Some(r) => (
            r.get("balance"),
            r.get("reward_pending_days"),
            r.get("reward_unlimited_until"),
        ),
        None => {
            let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM mobile_nodes WHERE id = $1)")
                .bind(auth.client_id)
                .fetch_one(&mut *tx)
                .await
                .map_err(AppError::Database)?;

            if exists {
                sqlx::query(
                    "INSERT INTO clients (id, email, balance_usd) VALUES ($1, $2, 0.0) ON CONFLICT DO NOTHING"
                )
                .bind(auth.client_id)
                .bind(format!("{}@byteaway.internal", auth.client_id))
                .execute(&mut *tx)
                .await
                .map_err(AppError::Database)?;

                (0.0, 0, None)
            } else {
                return Err(AppError::Unauthorized);
            }
        }
    };

    // Activate pending reward days on first/next VPN config request.
    if pending_days > 0 {
        let now = Utc::now();
        let base = match reward_unlimited_until {
            Some(until) if until > now => until,
            _ => now,
        };
        let new_until = base + Duration::days(pending_days as i64);

        sqlx::query(
            "UPDATE clients
             SET reward_unlimited_until = $1,
                 reward_pending_days = 0,
                 reward_first_activated_at = COALESCE(reward_first_activated_at, NOW())
             WHERE id = $2"
        )
        .bind(new_until)
        .bind(auth.client_id)
        .execute(&mut *tx)
        .await
        .map_err(AppError::Database)?;

        reward_unlimited_until = Some(new_until);
    }

    tx.commit().await.map_err(AppError::Database)?;

    // 2. Получаем или создаем назначенный IP через VPN registry
    let mut conn = state.redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let assigned_key = format!("vpn:assigned_ip:{}", auth.client_id);
    let assigned_ip: Option<String> = conn.get(&assigned_key).await.map_err(AppError::Redis)?;

    let assigned_ip = if let Some(ip) = assigned_ip {
        // Refresh TTL to keep existing assignment alive for active users
        let _: () = conn.expire(&assigned_key, 86_400).await.unwrap_or_default();
        ip
    } else {
        let next: i64 = redis::cmd("INCR").arg("vpn:ip:next").query_async(&mut conn).await.map_err(AppError::Redis)?;
        let host = 2 + ((next - 1) % 250);
        let ip = format!("10.8.0.{}", host);
        conn.set_ex::<_, _, ()>(&assigned_key, &ip, 86_400).await.map_err(AppError::Redis)?;
        ip
    };

    let node_active = state.registry.active_connections.contains_key(&auth.client_id);
    let paid = is_paid_tier(balance, reward_unlimited_until, node_active);

    let used_today: i64 = sqlx::query_scalar(
        "SELECT COALESCE(bytes_used, 0) FROM client_daily_traffic WHERE client_id = $1 AND traffic_date = CURRENT_DATE"
    )
    .bind(auth.client_id)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(AppError::Database)?
    .unwrap_or(0);

    let free_daily_limit_bytes = FREE_DAILY_LIMIT_BYTES;
    let free_daily_used_bytes = if paid { 0 } else { used_today.max(0) };
    let free_daily_remaining_bytes = if paid {
        0
    } else {
        (free_daily_limit_bytes - free_daily_used_bytes).max(0)
    };
    let tier = if paid { "paid" } else { "free" }.to_string();
    let max_speed_mbps = 0;

    if !paid && free_daily_remaining_bytes <= 0 {
        return Err(AppError::InsufficientBalance);
    }

    info!(
        "VPN config requested for client {} [tier={} speed={}Mbps free_rem={}B] ip={} host={}:{}",
        auth.client_id,
        tier,
        max_speed_mbps,
        free_daily_remaining_bytes,
        assigned_ip,
        state.vpn_public_host,
        state.vpn_port
    );

    let link = format!(
        "vless://{}@{}:{}?encryption=none&security=reality&sni={}&fp=chrome&pbk={}&sid={}&spx=%2F&flow=xtls-rprx-vision#ByteAway-VPN",
        state.vpn_client_uuid,
        state.vpn_public_host,
        state.vpn_port,
        reality_host,
        state.reality_public_key,
        state.reality_short_id
    );

    let xray_config_json = serde_json::json!({
        "log": {
            "level": "warn"
        },
        "dns": {
            "servers": [
                {
                    "tag": "dns-remote",
                    "address": "https://1.1.1.1/dns-query",
                    "detour": "proxy"
                },
                {
                    "tag": "dns-local",
                    "address": "8.8.8.8:53",
                    "detour": "direct"
                }
            ],
            "strategy": "ipv4_only"
        },
        "inbounds": [
            {
                "type": "socks",
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "listen_port": 10808,
                "sniff": true,
                "sniff_override_destination": true
            }
        ],
        "outbounds": [
            {
                "type": "vless",
                "tag": "proxy",
                "server": state.vpn_public_host,
                "server_port": state.vpn_port,
                "uuid": state.vpn_client_uuid,
                "flow": "xtls-rprx-vision",
                "packet_encoding": "xudp",
                "tls": {
                    "enabled": true,
                    "server_name": reality_host.clone(),
                    "utls": {
                        "enabled": true,
                        "fingerprint": "chrome"
                    },
                    "reality": {
                        "enabled": true,
                        "public_key": state.reality_public_key,
                        "short_id": state.reality_short_id
                    }
                }
            },
            {
                "type": "dns",
                "tag": "dns-out"
            },
            {
                "type": "direct",
                "tag": "direct"
            }
        ],
        "route": {
            "rules": [
                {
                    "protocol": "dns",
                    "outbound": "dns-out"
                },
                {
                    "inbound": "socks-in",
                    "outbound": "proxy"
                }
            ]
        }
    }).to_string();

    Ok(Json(VpnConfigResponse {
        vless_link: link,
        core_config_json: xray_config_json,
        assigned_ip,
        subnet: "10.8.0.0/24".to_string(),
        gateway: "10.8.0.1".to_string(),
        dns: vec!["1.1.1.1".to_string(), "8.8.8.8".to_string(), "9.9.9.9".to_string()],
        tier,
        max_speed_mbps,
        free_daily_limit_bytes,
        free_daily_used_bytes,
        free_daily_remaining_bytes,
        node_active,
    }))
}
