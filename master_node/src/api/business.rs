use crate::auth::AuthContext;
use crate::error::AppError;
use crate::state::AppState;
use axum::{extract::{State, Extension}, Json};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::sync::Arc;
use tracing::info;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct ReportErrorRequest {
    pub message: String,
    pub context: Option<serde_json::Value>,
}

/// POST /api/v1/business/report-error
/// B2B clients can report errors via curl or SDK
pub async fn report_business_error(
    State(state): State<Arc<AppState>>,
    Extension(auth): Extension<AuthContext>,
    Json(payload): Json<ReportErrorRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    info!(
        "B2B Error reported by client {}: {}",
        auth.client_id, payload.message
    );

    // Store in DB for later analysis
    sqlx::query(
        "INSERT INTO client_logs (client_id, level, message, metadata, created_at) \
         VALUES ($1, 'ERROR', $2, $3, NOW())",
    )
    .bind(auth.client_id)
    .bind(&payload.message)
    .bind(payload.context.unwrap_or(serde_json::json!({})))
    .execute(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    Ok(Json(serde_json::json!({ "status": "ok", "message": "Error report received" })))
}

/// Request to create new proxy credentials
#[derive(Deserialize)]
pub struct CreateProxyRequest {
    /// Optional label for this credential set
    pub label: Option<String>,
    /// Traffic limit in GB (0 = unlimited)
    pub traffic_limit_gb: Option<f64>,
    /// Allowed IP whitelist (CIDR notation)
    pub allowed_ips: Option<Vec<String>>,
    /// Allowed domain patterns (glob patterns)
    pub allowed_domains: Option<Vec<String>>,
}

/// Response with new proxy credentials
#[derive(Serialize)]
pub struct ProxyCredentialsResponse {
    pub credential_id: Uuid,
    /// SOCKS5 username (format: "country-type-credential_id")
    pub username: String,
    /// SOCKS5 password (API key)
    pub password: String,
    /// Proxy endpoint
    pub proxy_host: String,
    pub proxy_port: u16,
}

/// POST /api/v1/business/proxy-credentials
/// Creates new SOCKS5 credentials for B2B client
pub async fn create_proxy_credentials(
    State(state): State<Arc<AppState>>,
    Extension(auth): Extension<AuthContext>,
    Json(payload): Json<CreateProxyRequest>,
) -> Result<Json<ProxyCredentialsResponse>, AppError> {
    // 1. Check if client has sufficient balance
    let row = sqlx::query("SELECT balance_usd::float8 as balance FROM clients WHERE id = $1")
        .bind(auth.client_id)
        .fetch_one(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    let balance: f64 = row.get("balance");
    if balance < 0.01 {
        return Err(AppError::InsufficientBalance);
    }

    // 2. Generate new credential pair
    let credential_id = Uuid::new_v4();
    let api_key = format!("b2b_{}_{}", auth.client_id, credential_id);
    let key_hash = format!("{:x}", Sha256::digest(api_key.as_bytes()));

    // 3. Build username with optional country/type filter
    let country = "US"; // Default, could be from payload
    let conn_type = "wifi"; // Default
    let cred_str = credential_id.to_string();
    let username_part = cred_str.split('-').next().unwrap_or("unknown");
    let username = format!("{}-{}-{}", country, conn_type, username_part);

    // 4. Store in database
    sqlx::query(
        "INSERT INTO api_keys (key_hash, client_id, rate_limit_req_sec, created_at) 
         VALUES ($1, $2, $3, NOW())"
    )
    .bind(&key_hash)
    .bind(auth.client_id)
    .bind(100)
    .execute(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    // 5. Store additional metadata in Redis for fast lookup
    let mut conn = state.redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let meta_key = format!("proxy:cred:{}:{}", auth.client_id, credential_id);
    let meta = serde_json::json!({
        "client_id": auth.client_id,
        "credential_id": credential_id,
        "label": payload.label,
        "traffic_limit_gb": payload.traffic_limit_gb,
        "allowed_ips": payload.allowed_ips,
        "allowed_domains": payload.allowed_domains,
        "created_at": chrono::Utc::now().to_rfc3339(),
    });
    
    conn.set_ex::<_, _, ()>(&meta_key, meta.to_string(), 86400 * 30)
        .await
        .map_err(AppError::Redis)?;

    info!(
        "Created proxy credentials for client={}, credential_id={}",
        auth.client_id, credential_id
    );

    Ok(Json(ProxyCredentialsResponse {
        credential_id,
        username,
        password: api_key,
        proxy_host: state.vpn_public_host.clone(),
        proxy_port: 1080, // SOCKS5 port
    }))
}

/// List all proxy credentials for a client
#[derive(Serialize)]
pub struct ProxyCredentialListItem {
    pub credential_id: Uuid,
    pub label: Option<String>,
    pub username: String,
    pub created_at: String,
    pub traffic_limit_gb: Option<f64>,
}

#[derive(Serialize)]
pub struct ListProxyCredentialsResponse {
    pub credentials: Vec<ProxyCredentialListItem>,
}

/// GET /api/v1/business/proxy-credentials
pub async fn list_proxy_credentials(
    State(state): State<Arc<AppState>>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<ListProxyCredentialsResponse>, AppError> {
    let rows = sqlx::query(
        "SELECT ak.key_hash, ak.created_at, ak.rate_limit_req_sec
         FROM api_keys ak
         WHERE ak.client_id = $1
         ORDER BY ak.created_at DESC"
    )
    .bind(auth.client_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let mut credentials = Vec::new();

    for row in rows {
        let key_hash: String = row.get("key_hash");
        let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");
        
        // Extract credential_id from key_hash pattern (simplified)
        let cred_id = Uuid::new_v4(); // In production, parse from key_hash
        
        credentials.push(ProxyCredentialListItem {
            credential_id: cred_id,
            label: None, // Could be fetched from Redis
            username: format!("US-wifi-{}", &key_hash[..8]),
            created_at: created_at.to_rfc3339(),
            traffic_limit_gb: None,
        });
    }

    Ok(Json(ListProxyCredentialsResponse { credentials }))
}
