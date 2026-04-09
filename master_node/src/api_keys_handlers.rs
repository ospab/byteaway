use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{get, post, put, delete},
    Router,
};
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use std::sync::Arc;

use crate::api_keys::{ApiKeyManager, CreateApiKeyRequest, ApiKeyResponse, ApiKeyUsage};
use crate::auth::AdminAuth;

pub fn api_keys_router() -> Router<Arc<ApiKeyManager>> {
    Router::new()
        .route("/", post(create_api_key))
        .route("/", get(list_api_keys))
        .route("/:key_id", get(get_api_key))
        .route("/:key_id/balance", put(update_balance))
        .route("/:key_id/stats", get(get_usage_stats))
        .route("/:key_id/toggle", put(toggle_api_key))
        .route("/:key_id", delete(delete_api_key))
}

#[derive(Deserialize)]
struct UpdateBalanceRequest {
    amount_usd: f64,
}

#[derive(Deserialize)]
struct UsageStatsQuery {
    start_date: Option<DateTime<Utc>>,
    end_date: Option<DateTime<Utc>>,
}

/// Создать новый API ключ (только для админа)
pub async fn create_api_key(
    State(manager): State<Arc<ApiKeyManager>>,
    _auth: AdminAuth,
    Json(request): Json<CreateApiKeyRequest>,
) -> Result<Json<ApiKeyResponse>, StatusCode> {
    match manager.create_api_key(request).await {
        Ok(api_key) => Ok(Json(api_key)),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Получить список всех API ключей (только для админа)
pub async fn list_api_keys(
    State(manager): State<Arc<ApiKeyManager>>,
    _auth: AdminAuth,
) -> Result<Json<Vec<ApiKeyResponse>>, StatusCode> {
    match manager.list_api_keys().await {
        Ok(keys) => Ok(Json(keys)),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Получить информацию об API ключе
pub async fn get_api_key(
    State(manager): State<Arc<ApiKeyManager>>,
    Path(key_id): Path<String>,
) -> Result<Json<ApiKeyResponse>, StatusCode> {
    match manager.list_api_keys().await {
        Ok(keys) => {
            if let Some(key) = keys.into_iter().find(|k| k.key_id == key_id) {
                Ok(Json(key))
            } else {
                Err(StatusCode::NOT_FOUND)
            }
        }
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Обновить баланс API ключа
pub async fn update_balance(
    State(manager): State<Arc<ApiKeyManager>>,
    Path(key_id): Path<String>,
    _auth: AdminAuth,
    Json(request): Json<UpdateBalanceRequest>,
) -> Result<StatusCode, StatusCode> {
    match manager.update_balance(&key_id, request.amount_usd).await {
        Ok(_) => Ok(StatusCode::OK),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Получить статистику использования API ключа
pub async fn get_usage_stats(
    State(manager): State<Arc<ApiKeyManager>>,
    Path(key_id): Path<String>,
    query: axum::extract::Query<UsageStatsQuery>,
) -> Result<Json<ApiKeyUsage>, StatusCode> {
    let start_date = query.start_date.unwrap_or_else(|| Utc::now() - chrono::Duration::days(30));
    let end_date = query.end_date.unwrap_or_else(|| Utc::now());

    match manager.get_usage_stats(&key_id, start_date, end_date).await {
        Ok(stats) => Ok(Json(stats)),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Блокировать/разблокировать API ключ
pub async fn toggle_api_key(
    State(manager): State<Arc<ApiKeyManager>>,
    Path(key_id): Path<String>,
    _auth: AdminAuth,
    Json(is_active): Json<bool>,
) -> Result<StatusCode, StatusCode> {
    match manager.toggle_api_key(&key_id, is_active).await {
        Ok(_) => Ok(StatusCode::OK),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Удалить API ключ
pub async fn delete_api_key(
    State(manager): State<Arc<ApiKeyManager>>,
    Path(key_id): Path<String>,
    _auth: AdminAuth,
) -> Result<StatusCode, StatusCode> {
    match manager.delete_api_key(&key_id).await {
        Ok(_) => Ok(StatusCode::OK),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Middleware для проверки API ключа в B2B запросах
pub async fn api_key_auth(
    State(manager): State<Arc<ApiKeyManager>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
    request: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> Result<axum::response::Response, StatusCode> {
    // Получаем API ключ из заголовка Authorization
    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|header| header.to_str().ok())
        .and_then(|header| {
            if header.starts_with("Bearer ") {
                Some(&header[7..])
            } else {
                None
            }
        });

    let api_key = match auth_header {
        Some(key) => key,
        None => return Err(StatusCode::UNAUTHORIZED),
    };

    // Проверяем валидность ключа
    match manager.validate_api_key(api_key).await {
        Ok(Some(key_info)) => {
            // Проверяем лимиты
            if key_info.traffic_used_gb >= key_info.traffic_limit_gb {
                return Err(StatusCode::PAYMENT_REQUIRED);
            }

            // Проверяем количество активных сессий
            if key_info.max_sessions > 0 {
                let active_sessions = get_active_sessions_count(&manager.pool, &key_info.key_id).await;
                if active_sessions >= key_info.max_sessions as i64 {
                    return Err(StatusCode::TOO_MANY_REQUESTS);
                }
            }

            // Продолжаем выполнение запроса
            Ok(next.run(request).await)
        }
        Ok(None) => Err(StatusCode::UNAUTHORIZED),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

async fn get_active_sessions_count(
    pool: &sqlx::PgPool,
    key_id: &str,
) -> i64 {
    sqlx::query_scalar!(
        "SELECT COUNT(*) FROM api_sessions 
         WHERE api_key_id = (SELECT id FROM api_keys WHERE key_id = $1) 
         AND is_active = true",
        key_id
    )
    .fetch_one(pool)
    .await
    .unwrap_or(0)
}

/// Публичный эндпоинт для проверки баланса (доступен по API ключу)
pub async fn public_get_balance(
    State(manager): State<Arc<ApiKeyManager>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Этот эндпоинт использует middleware api_key_auth
    // Здесь мы просто возвращаем баланс из контекста запроса
    // TODO: Получить key_info из middleware
    
    Ok(Json(serde_json::json!({
        "balance_usd": 25.50,
        "vpn_days_remaining": 30,
        "total_traffic_gb": 150.25
    })))
}

/// Публичный эндпоинт для получения статистики (доступен по API ключу)
pub async fn public_get_stats(
    State(manager): State<Arc<ApiKeyManager>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // TODO: Получить key_info из middleware
    
    Ok(Json(serde_json::json!({
        "shared_traffic_gb": 2.5,
        "current_speed_mbps": 5.2,
        "active_sessions": 3,
        "uptime_seconds": 3600
    })))
}

pub fn public_api_router() -> Router<Arc<ApiKeyManager>> {
    Router::new()
        .route("/balance", get(public_get_balance))
        .route("/stats", get(public_get_stats))
        .layer(axum::middleware::from_fn_with_state(
            Arc::clone(&manager),
            api_key_auth,
        ))
}
