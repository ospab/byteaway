use axum::{extract::{State, Query}, Extension, Json};
use crate::auth::AuthContext;
use crate::error::AppError;
use crate::state::AppState;
use redis::AsyncCommands;
use serde::{Serialize, Deserialize};
use sqlx::Row;
use std::sync::Arc;
use tracing::info;

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

#[derive(Deserialize)]
pub struct RegisterClientRequest {
    pub email: String,
    #[allow(dead_code)]
    #[serde(default)]
    pub referral_code: Option<String>,
}

#[derive(Deserialize)]
pub struct LoginClientRequest {
    pub email: String,
}

/// POST /api/v1/auth/register — Регистрация B2C клиента по Email
pub async fn register_client(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterClientRequest>,
) -> Result<Json<RegisterNodeResponse>, AppError> {
    let client_id = uuid::Uuid::new_v4();
    
    // Пытаемся создать клиента. Если email уже есть — возвращаем существующего.
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO clients (id, email, balance_usd) \
         VALUES ($1, $2, 0.0) \
         ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email \
         RETURNING id",
    )
    .bind(client_id)
    .bind(&payload.email)
    .fetch_one(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    Ok(Json(RegisterNodeResponse {
        node_id: id,
        token: payload.email,
    }))
}

/// POST /api/v1/auth/login — Логин B2C клиента по Email
pub async fn login_client(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginClientRequest>,
) -> Result<Json<RegisterNodeResponse>, AppError> {
    let row = sqlx::query("SELECT id FROM clients WHERE email = $1")
        .bind(&payload.email)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    match row {
        Some(r) => {
            let id: uuid::Uuid = r.get("id");
            Ok(Json(RegisterNodeResponse {
                node_id: id,
                token: payload.email,
            }))
        }
        None => Err(AppError::Unauthorized),
    }
}

/// POST /api/v1/auth/register-node — Регистрация B2C ноды по Device ID
pub async fn register_node(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterNodeRequest>,
) -> Result<Json<RegisterNodeResponse>, AppError> {
    // Если device_id — валидный UUID, используем его.
    // Если нет (например, Android ID или серийник) — генерируем стабильный UUID v5 от него.
    let device_uuid = match uuid::Uuid::parse_str(&payload.device_id) {
        Ok(u) => u,
        Err(_) => {
            // Используем фиксированный неймспейс для генерации стабильных UUID из произвольных строк
            uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, payload.device_id.as_bytes())
        }
    };

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

    // В учебных целях возвращаем device_id как токен, с которым можно ходить в /balance
    // В продакшене тут должен генерироваться JWT.
    Ok(Json(RegisterNodeResponse {
        node_id,
        token: payload.device_id,
    }))
}

/// GET /api/v1/balance — баланс текущего клиента (по API ключу)
pub async fn get_balance(
    State(state): State<Arc<AppState>>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<BalanceResponse>, AppError> {
    // Пытаемся плавно найти баланс. Если клиента нет (старый переходный период), создаем его.
    let balance: f64 = match sqlx::query_scalar::<_, f64>("SELECT balance_usd::float8 FROM clients WHERE id = $1")
        .bind(auth.client_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(AppError::Database)? 
    {
        Some(b) => b,
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
                0.0
            } else {
                return Err(AppError::Unauthorized);
            }
        }
    };

    Ok(Json(BalanceResponse {
        client_id: auth.client_id.to_string(),
        balance_usd: balance,
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
    pub assigned_ip: String,
    pub subnet: String,
    pub gateway: String,
    pub dns: Vec<String>,
    pub tier: String,
    pub max_speed_mbps: i32,
}

pub async fn get_vpn_config(
    State(state): State<Arc<AppState>>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<VpnConfigResponse>, AppError> {
    // 1. Get client balance (free tier allowed with $0)
    let row = sqlx::query("SELECT balance_usd::float8 as balance FROM clients WHERE id = $1")
        .bind(auth.client_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    let balance: f64 = match row {
        Some(r) => r.get("balance"),
        None => return Err(AppError::Unauthorized),
    };

    // 2. Получаем или создаем назначенный IP через VPN registry
    let mut conn = state.redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let assigned_key = format!("vpn:assigned_ip:{}", auth.client_id);
    let assigned_ip: Option<String> = conn.get(&assigned_key).await.map_err(AppError::Redis)?;

    let assigned_ip = if let Some(ip) = assigned_ip {
        ip
    } else {
        let next: i64 = redis::cmd("INCR").arg("vpn:ip:next").query_async(&mut conn).await.map_err(AppError::Redis)?;
        let host = 2 + ((next - 1) % 250);
        let ip = format!("10.8.0.{}", host);
        conn.set::<_, _, ()>(&assigned_key, &ip).await.map_err(AppError::Redis)?;
        ip
    };

    // 3. Определяем tier клиента (free = баланс < $1, paid = баланс >= $1)
    let (tier, max_speed_mbps) = if balance >= 1.0 {
        ("paid".to_string(), 0) // 0 = unlimited
    } else {
        ("free".to_string(), 10) // 10 Mbps limit
    };

    info!(
        "VPN config requested for client {} [tier={} speed={}Mbps] ip={}",
        auth.client_id, tier, max_speed_mbps, assigned_ip
    );

    let link = format!(
        "vless://{}@{}:{}?encryption=none&security=reality&sni=google.com&fp=chrome&pbk={}&sid={}#ByteAway-VPN",
        state.vpn_client_uuid,
        state.vpn_public_host,
        state.vpn_port,
        state.reality_public_key,
        state.reality_short_id
    );

    Ok(Json(VpnConfigResponse {
        vless_link: link,
        assigned_ip,
        subnet: "10.8.0.0/24".to_string(),
        gateway: "10.8.0.1".to_string(),
        dns: vec!["8.8.8.8".to_string(), "1.1.1.1".to_string()],
        tier,
        max_speed_mbps,
    }))
}
