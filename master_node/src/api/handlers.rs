use axum::{Json, Extension, extract::State, response::IntoResponse};
use crate::auth::AuthContext;
use crate::error::AppError;
use crate::state::AppState;
use redis::AsyncCommands;
use serde::Serialize;
use sqlx::Row;
use std::sync::Arc;

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

/// POST /api/v1/auth/register-node — Регистрация B2C ноды по Device ID
pub async fn register_node(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterNodeRequest>,
) -> Result<impl IntoResponse, AppError> {
    // 1. Ищем существующую ноду или создаем новую
    let row = sqlx::query(
        "INSERT INTO mobile_nodes (id, device_id) \
         VALUES ($1, $2) \
         ON CONFLICT (device_id) DO UPDATE SET device_id = EXCLUDED.device_id \
         RETURNING id",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(&payload.device_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let node_id: uuid::Uuid = row.get("id");

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
) -> Result<impl IntoResponse, AppError> {
    let row = sqlx::query("SELECT balance_usd::float8 as balance FROM clients WHERE id = $1")
        .bind(auth.client_id)
        .fetch_one(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    let balance: f64 = row.get("balance");

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
) -> Result<impl IntoResponse, AppError> {
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
