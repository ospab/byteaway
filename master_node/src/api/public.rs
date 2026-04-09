use axum::{
    extract::{Query, State},
    http::{HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sha2::Digest;
use std::sync::Arc;
use uuid::Uuid;

use crate::error::AppError;
use crate::state::AppState;

use super::turnstile::verify_turnstile_token;

const DOWNLOAD_TICKET_TTL_SECONDS: u64 = 120;

#[derive(Deserialize)]
pub struct CreateDownloadTicketRequest {
    pub captcha_token: String,
}

#[derive(Serialize)]
pub struct CreateDownloadTicketResponse {
    pub download_url: String,
    pub expires_in_seconds: u64,
}

#[derive(Deserialize)]
pub struct DownloadQuery {
    pub ticket: String,
}

#[derive(Serialize, Deserialize)]
struct DownloadTicketMeta {
    ip: String,
    ua_hash: String,
}

fn hash_ua(ua: &str) -> String {
    let digest = sha2::Sha256::digest(ua.as_bytes());
    hex::encode(digest)
}

pub async fn create_download_ticket(
    State(state): State<Arc<AppState>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
    headers: HeaderMap,
    Json(payload): Json<CreateDownloadTicketRequest>,
) -> Result<Json<CreateDownloadTicketResponse>, AppError> {
    verify_turnstile_token(&state, &payload.captcha_token, &addr.ip().to_string()).await?;

    let ticket = format!("dl_{}", Uuid::new_v4().simple());
    let redis_key = format!("download:ticket:{}", ticket);

    let mut conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let ua = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();

    let meta = DownloadTicketMeta {
        ip: addr.ip().to_string(),
        ua_hash: hash_ua(ua),
    };

    let meta_json = serde_json::to_string(&meta)
        .map_err(|e| AppError::Unexpected(anyhow::anyhow!("failed to encode ticket metadata: {}", e)))?;

    conn.set_ex::<_, _, ()>(&redis_key, meta_json, DOWNLOAD_TICKET_TTL_SECONDS)
        .await
        .map_err(AppError::Redis)?;

    Ok(Json(CreateDownloadTicketResponse {
        download_url: format!("/api/v1/public/downloads/byteaway-release.apk?ticket={}", ticket),
        expires_in_seconds: DOWNLOAD_TICKET_TTL_SECONDS,
    }))
}

pub async fn download_apk_with_ticket(
    State(state): State<Arc<AppState>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
    headers: HeaderMap,
    Query(query): Query<DownloadQuery>,
) -> Result<impl IntoResponse, AppError> {
    if query.ticket.trim().is_empty() {
        return Err(AppError::BadRequest("ticket is required".to_string()));
    }

    let redis_key = format!("download:ticket:{}", query.ticket.trim());
    let mut conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let ticket_meta_json: Option<String> = conn.get(&redis_key).await.map_err(AppError::Redis)?;
    let ticket_meta_json = match ticket_meta_json {
        Some(v) => v,
        None => {
            return Err(AppError::Unauthorized);
        }
    };

    let ticket_meta: DownloadTicketMeta = serde_json::from_str(&ticket_meta_json)
        .map_err(|_| AppError::Unauthorized)?;

    let request_ua = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();

    if ticket_meta.ip != addr.ip().to_string() || ticket_meta.ua_hash != hash_ua(request_ua) {
        return Err(AppError::Unauthorized);
    }

    let _: () = conn.del(&redis_key).await.map_err(AppError::Redis)?;

    let mut response = Response::new(axum::body::Body::empty());
    *response.status_mut() = StatusCode::OK;
    response.headers_mut().insert(
        "X-Accel-Redirect",
        HeaderValue::from_static("/_protected_downloads/byteaway-release.apk"),
    );
    response.headers_mut().insert(
        "Content-Type",
        HeaderValue::from_static("application/vnd.android.package-archive"),
    );
    response.headers_mut().insert(
        "Content-Disposition",
        HeaderValue::from_static("attachment; filename=byteaway-release.apk"),
    );

    Ok(response)
}
