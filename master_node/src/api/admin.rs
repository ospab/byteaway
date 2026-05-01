use axum::{
    extract::{Request, State},
    http::HeaderMap,
    Json,
    middleware::Next,
    response::Response,
};
use serde::{Serialize, Deserialize};
use std::sync::Arc;
use crate::error::AppError;
use crate::state::AppState;
use sqlx::Row;

#[derive(Deserialize)]
pub struct AdminAuth {
    #[serde(default)]
    pub x_admin_key: Option<String>,
}

#[derive(Serialize)]
pub struct SystemStats {
    pub total_clients: i64,
    pub active_devices: i64,
    pub total_traffic_gb: String,
    pub total_balance_usd: String,
    pub active_sessions: i64,
}

#[derive(Serialize)]
pub struct ClientInfo {
    pub id: uuid::Uuid,
    pub email: String,
    pub balance_usd: String,
    pub created_at: String,
    pub device_count: i64,
}

#[derive(Serialize)]
pub struct DeviceInfo {
    pub id: uuid::Uuid,
    pub client_id: uuid::Uuid,
    pub hwid: String,
    pub vless_uuid: String,
    pub device_name: Option<String>,
    pub os_type: Option<String>,
    pub is_active: bool,
    pub is_blocked: bool,
    pub last_seen_at: String,
}

pub async fn require_admin_key(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = headers.get("x-admin-key")
        .or_else(|| headers.get("X-Admin-Key"))
        .and_then(|h| h.to_str().ok());

    match auth_header {
        Some(key) if key == state.admin_api_key => Ok(next.run(req).await),
        _ => Err(AppError::Unauthorized),
    }
}

pub async fn get_system_stats(
    State(state): State<Arc<AppState>>,
) -> Result<Json<SystemStats>, AppError> {
    let total_clients: i64 = sqlx::query("SELECT COUNT(*) FROM clients")
        .fetch_one(&state.db_pool)
        .await
        .map(|r| r.get(0))
        .unwrap_or(0);

    let active_devices: i64 = sqlx::query("SELECT COUNT(*) FROM devices WHERE is_active = TRUE")
        .fetch_one(&state.db_pool)
        .await
        .map(|r| r.get(0))
        .unwrap_or(0);

    let total_traffic_gb: String = sqlx::query("SELECT COALESCE(SUM(bytes_used), 0) / 1073741824.0::text FROM traffic_history")
        .fetch_one(&state.db_pool)
        .await
        .map(|r| r.get(0))
        .unwrap_or("0.0".to_string());

    let total_balance_usd: String = sqlx::query("SELECT COALESCE(SUM(balance_usd), 0)::text FROM clients")
        .fetch_one(&state.db_pool)
        .await
        .map(|r| r.get(0))
        .unwrap_or("0.0".to_string());

    let active_sessions: i64 = sqlx::query("SELECT COUNT(*) FROM vpn_sessions WHERE is_active = TRUE")
        .fetch_one(&state.db_pool)
        .await
        .map(|r| r.get(0))
        .unwrap_or(0);

    Ok(Json(SystemStats {
        total_clients,
        active_devices,
        total_traffic_gb,
        total_balance_usd,
        active_sessions,
    }))
}

pub async fn list_clients(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<ClientInfo>>, AppError> {
    let rows = sqlx::query(
        "SELECT c.id, c.email, c.balance_usd::text, c.created_at, COUNT(d.id) as device_count 
         FROM clients c 
         LEFT JOIN devices d ON c.id = d.client_id 
         GROUP BY c.id 
         ORDER BY c.created_at DESC 
         LIMIT 100"
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let clients: Vec<ClientInfo> = rows.iter().map(|r| ClientInfo {
        id: r.try_get("id").unwrap_or(uuid::Uuid::nil()),
        email: r.try_get("email").unwrap_or_default(),
        balance_usd: r.try_get("balance_usd").unwrap_or_default(),
        created_at: r.try_get("created_at").unwrap_or_default(),
        device_count: r.try_get("device_count").unwrap_or(0),
    }).collect();

    Ok(Json(clients))
}

pub async fn list_devices(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<DeviceInfo>>, AppError> {
    let rows = sqlx::query(
        "SELECT id, client_id, hwid, vless_uuid, device_name, os_type, is_active, is_blocked, last_seen_at 
         FROM devices 
         ORDER BY last_seen_at DESC 
         LIMIT 100"
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let devices: Vec<DeviceInfo> = rows.iter().map(|r| DeviceInfo {
        id: r.try_get("id").unwrap_or(uuid::Uuid::nil()),
        client_id: r.try_get("client_id").unwrap_or(uuid::Uuid::nil()),
        hwid: r.try_get("hwid").unwrap_or_default(),
        vless_uuid: r.try_get("vless_uuid").unwrap_or_default(),
        device_name: r.try_get("device_name").ok(),
        os_type: r.try_get("os_type").ok(),
        is_active: r.try_get("is_active").unwrap_or(false),
        is_blocked: r.try_get("is_blocked").unwrap_or(false),
        last_seen_at: r.try_get("last_seen_at").unwrap_or_default(),
    }).collect();

    Ok(Json(devices))
}

pub async fn block_device(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(device_id): axum::extract::Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    sqlx::query("UPDATE devices SET is_blocked = TRUE WHERE id = $1")
        .bind(&device_id)
        .execute(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    Ok(Json(serde_json::json!({"status": "blocked", "device_id": device_id})))
}

pub async fn unblock_device(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(device_id): axum::extract::Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    sqlx::query("UPDATE devices SET is_blocked = FALSE WHERE id = $1")
        .bind(&device_id)
        .execute(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    Ok(Json(serde_json::json!({"status": "unblocked", "device_id": device_id})))
}
