use axum::{
    extract::{Path, State},
    http::HeaderMap,
    Json,
};
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{SaltString};
use rand::rngs::OsRng;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::sync::Arc;
use uuid::Uuid;

use crate::auth::Authenticator;
use crate::error::AppError;
use crate::state::AppState;
use super::turnstile::verify_turnstile_token;

const SESSION_TTL_SECONDS: i64 = 60 * 60 * 24; // 24h
const LOGIN_WINDOW_SECONDS: u64 = 15 * 60; // 15 min
const LOGIN_MAX_ATTEMPTS: i64 = 8;

#[derive(Deserialize)]
pub struct RegisterBusinessRequest {
    #[serde(alias = "companyName")]
    pub company_name: String,
    pub email: String,
    pub password: String,
    #[serde(default, alias = "captchaToken")]
    pub captcha_token: String,
}

#[derive(Deserialize)]
pub struct LoginBusinessRequest {
    pub email: String,
    pub password: String,
    #[serde(default, alias = "captchaToken")]
    pub captcha_token: String,
}

#[derive(Deserialize)]
pub struct CreateBusinessTokenRequest {
    pub label: Option<String>,
    pub country: Option<String>,
}

#[derive(Serialize)]
pub struct BusinessAuthResponse {
    pub session_token: String,
    pub expires_at: String,
    pub client_id: String,
    pub email: String,
    pub company_name: String,
}

#[derive(Serialize)]
pub struct BusinessTokenResponse {
    pub credential_id: String,
    pub token: String,
    pub username: String,
    pub proxy_host: String,
    pub proxy_port: u16,
    pub created_at: String,
    pub label: Option<String>,
}

#[derive(Serialize)]
pub struct BusinessTokenListItem {
    pub credential_id: String,
    pub username: String,
    pub created_at: String,
    pub label: Option<String>,
}

#[derive(Serialize)]
pub struct BusinessTokenListResponse {
    pub tokens: Vec<BusinessTokenListItem>,
}

struct SessionAccount {
    account_id: Uuid,
    client_id: Uuid,
    company_name: String,
    email: String,
}

fn normalize_email(email: &str) -> String {
    email.trim().to_lowercase()
}

fn validate_password(password: &str) -> Result<(), AppError> {
    if password.len() < 10 {
        return Err(AppError::BadRequest("password must be at least 10 characters".to_string()));
    }

    let has_letter = password.chars().any(|c| c.is_ascii_alphabetic());
    let has_digit = password.chars().any(|c| c.is_ascii_digit());
    if !has_letter || !has_digit {
        return Err(AppError::BadRequest("password must contain letters and numbers".to_string()));
    }

    Ok(())
}

fn extract_bearer(headers: &HeaderMap) -> Result<String, AppError> {
    let auth = headers
        .get("authorization")
        .and_then(|h| h.to_str().ok())
        .ok_or(AppError::Unauthorized)?;

    let token = auth.strip_prefix("Bearer ").ok_or(AppError::Unauthorized)?;
    if token.trim().is_empty() {
        return Err(AppError::Unauthorized);
    }

    Ok(token.trim().to_string())
}

fn hash_session_token(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    hex::encode(digest)
}

fn issue_plain_session_token() -> String {
    format!("bsn_{}_{}", Uuid::new_v4().simple(), Uuid::new_v4().simple())
}

fn derive_username(country: &str, credential_id: Uuid) -> String {
    let short = credential_id.simple().to_string();
    format!("{}-biz-{}", country, &short[..12])
}

async fn enforce_login_rate_limit(
    redis_client: &redis::Client,
    client_ip: &str,
    email: &str,
) -> Result<(), AppError> {
    let mut conn = redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let scope = format!("{}:{}", client_ip, email);
    let ban_key = format!("business:auth:ban:{}", scope);
    let fail_key = format!("business:auth:fails:{}", scope);

    let banned: Option<bool> = conn.get(&ban_key).await.map_err(AppError::Redis)?;
    if banned.unwrap_or(false) {
        return Err(AppError::TooManyRequests);
    }

    let current: Option<i64> = conn.get(&fail_key).await.map_err(AppError::Redis)?;
    if current.unwrap_or(0) >= LOGIN_MAX_ATTEMPTS {
        let _: () = conn.set_ex(&ban_key, true, LOGIN_WINDOW_SECONDS).await.map_err(AppError::Redis)?;
        let _: () = conn.del(&fail_key).await.map_err(AppError::Redis)?;
        return Err(AppError::TooManyRequests);
    }

    Ok(())
}

async fn record_login_failure(
    redis_client: &redis::Client,
    client_ip: &str,
    email: &str,
) -> Result<(), AppError> {
    let mut conn = redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let scope = format!("{}:{}", client_ip, email);
    let fail_key = format!("business:auth:fails:{}", scope);
    let fails: i64 = conn.incr(&fail_key, 1).await.map_err(AppError::Redis)?;
    let _: () = conn.expire(&fail_key, LOGIN_WINDOW_SECONDS as i64).await.map_err(AppError::Redis)?;

    if fails >= LOGIN_MAX_ATTEMPTS {
        let ban_key = format!("business:auth:ban:{}", scope);
        let _: () = conn.set_ex(&ban_key, true, LOGIN_WINDOW_SECONDS).await.map_err(AppError::Redis)?;
        let _: () = conn.del(&fail_key).await.map_err(AppError::Redis)?;
    }

    Ok(())
}

async fn clear_login_failures(
    redis_client: &redis::Client,
    client_ip: &str,
    email: &str,
) -> Result<(), AppError> {
    let mut conn = redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(AppError::Redis)?;

    let scope = format!("{}:{}", client_ip, email);
    let fail_key = format!("business:auth:fails:{}", scope);
    let _: () = conn.del(&fail_key).await.map_err(AppError::Redis)?;
    Ok(())
}

async fn create_session(
    state: &Arc<AppState>,
    account_id: Uuid,
) -> Result<(String, chrono::DateTime<chrono::Utc>), AppError> {
    let session_token = issue_plain_session_token();
    let session_hash = hash_session_token(&session_token);
    let now = chrono::Utc::now();
    let expires_at = now + chrono::Duration::seconds(SESSION_TTL_SECONDS);

    sqlx::query(
        "INSERT INTO business_sessions (id, account_id, session_hash, expires_at, created_at)
         VALUES ($1, $2, $3, $4, NOW())"
    )
    .bind(Uuid::new_v4())
    .bind(account_id)
    .bind(session_hash)
    .bind(expires_at)
    .execute(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    Ok((session_token, expires_at))
}

async fn require_business_session(
    state: &Arc<AppState>,
    headers: &HeaderMap,
) -> Result<SessionAccount, AppError> {
    let token = extract_bearer(headers)?;
    let token_hash = hash_session_token(&token);

    let row = sqlx::query(
        "SELECT ba.id as account_id, ba.client_id, ba.company_name, ba.email
         FROM business_sessions bs
         JOIN business_accounts ba ON ba.id = bs.account_id
         WHERE bs.session_hash = $1
           AND bs.revoked_at IS NULL
           AND bs.expires_at > NOW()
           AND ba.is_active = TRUE"
    )
    .bind(token_hash)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let row = row.ok_or(AppError::Unauthorized)?;

    Ok(SessionAccount {
        account_id: row.get("account_id"),
        client_id: row.get("client_id"),
        company_name: row.get("company_name"),
        email: row.get("email"),
    })
}

pub async fn register_business(
    State(state): State<Arc<AppState>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
    headers: HeaderMap,
    Json(payload): Json<RegisterBusinessRequest>,
) -> Result<Json<BusinessAuthResponse>, AppError> {
    let email = normalize_email(&payload.email);
    let company_name = payload.company_name.trim().to_string();

    if company_name.len() < 2 {
        return Err(AppError::BadRequest("company_name is too short".to_string()));
    }
    if !email.contains('@') {
        return Err(AppError::BadRequest("invalid email".to_string()));
    }
    validate_password(&payload.password)?;

    // Support clients that send Turnstile token in either JSON body or standard header.
    let captcha_token = if payload.captcha_token.trim().is_empty() {
        headers
            .get("cf-turnstile-response")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string()
    } else {
        payload.captcha_token.clone()
    };
    verify_turnstile_token(&state, &captcha_token, &addr.ip().to_string()).await?;

    enforce_login_rate_limit(&state.redis_client, &addr.ip().to_string(), &email).await?;

    let mut tx = state.db_pool.begin().await.map_err(AppError::Database)?;

    let existing: Option<Uuid> = sqlx::query_scalar("SELECT id FROM business_accounts WHERE email = $1")
        .bind(&email)
        .fetch_optional(&mut *tx)
        .await
        .map_err(AppError::Database)?;

    if existing.is_some() {
        record_login_failure(&state.redis_client, &addr.ip().to_string(), &email).await?;
        return Err(AppError::BadRequest("email is already registered".to_string()));
    }

    let account_id = Uuid::new_v4();
    let client_id = Uuid::new_v4();

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(payload.password.as_bytes(), &salt)
        .map_err(|_| AppError::Unexpected(anyhow::anyhow!("failed to hash password")))?
        .to_string();

    sqlx::query(
        "INSERT INTO clients (id, email, balance_usd, created_at)
         VALUES ($1, $2, 0.0, NOW())"
    )
    .bind(client_id)
    .bind(&email)
    .execute(&mut *tx)
    .await
    .map_err(AppError::Database)?;

    sqlx::query(
        "INSERT INTO business_accounts (id, client_id, company_name, email, password_hash, is_active, created_at)
         VALUES ($1, $2, $3, $4, $5, TRUE, NOW())"
    )
    .bind(account_id)
    .bind(client_id)
    .bind(&company_name)
    .bind(&email)
    .bind(password_hash)
    .execute(&mut *tx)
    .await
    .map_err(AppError::Database)?;

    tx.commit().await.map_err(AppError::Database)?;

    let (session_token, expires_at) = create_session(&state, account_id).await?;
    clear_login_failures(&state.redis_client, &addr.ip().to_string(), &email).await?;

    Ok(Json(BusinessAuthResponse {
        session_token,
        expires_at: expires_at.to_rfc3339(),
        client_id: client_id.to_string(),
        email,
        company_name,
    }))
}

pub async fn login_business(
    State(state): State<Arc<AppState>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
    headers: HeaderMap,
    Json(payload): Json<LoginBusinessRequest>,
) -> Result<Json<BusinessAuthResponse>, AppError> {
    let email = normalize_email(&payload.email);
    // Support clients that send Turnstile token in either JSON body or standard header.
    let captcha_token = if payload.captcha_token.trim().is_empty() {
        headers
            .get("cf-turnstile-response")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string()
    } else {
        payload.captcha_token.clone()
    };
    verify_turnstile_token(&state, &captcha_token, &addr.ip().to_string()).await?;

    enforce_login_rate_limit(&state.redis_client, &addr.ip().to_string(), &email).await?;

    let row = sqlx::query(
        "SELECT id, client_id, company_name, email, password_hash
         FROM business_accounts
         WHERE email = $1 AND is_active = TRUE"
    )
    .bind(&email)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let row = match row {
        Some(r) => r,
        None => {
            record_login_failure(&state.redis_client, &addr.ip().to_string(), &email).await?;
            return Err(AppError::Unauthorized);
        }
    };

    let password_hash: String = row.get("password_hash");
    let parsed_hash = PasswordHash::new(&password_hash)
        .map_err(|_| AppError::Unexpected(anyhow::anyhow!("invalid stored password hash")))?;

    let verified = Argon2::default()
        .verify_password(payload.password.as_bytes(), &parsed_hash)
        .is_ok();

    if !verified {
        record_login_failure(&state.redis_client, &addr.ip().to_string(), &email).await?;
        return Err(AppError::Unauthorized);
    }

    let account_id: Uuid = row.get("id");
    let client_id: Uuid = row.get("client_id");
    let company_name: String = row.get("company_name");
    let account_email: String = row.get("email");

    sqlx::query("UPDATE business_accounts SET last_login_at = NOW() WHERE id = $1")
        .bind(account_id)
        .execute(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    let (session_token, expires_at) = create_session(&state, account_id).await?;
    clear_login_failures(&state.redis_client, &addr.ip().to_string(), &email).await?;

    Ok(Json(BusinessAuthResponse {
        session_token,
        expires_at: expires_at.to_rfc3339(),
        client_id: client_id.to_string(),
        email: account_email,
        company_name,
    }))
}

pub async fn create_business_api_token(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateBusinessTokenRequest>,
) -> Result<Json<BusinessTokenResponse>, AppError> {
    let account = require_business_session(&state, &headers).await?;

    let label = payload
        .label
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty());

    let country = payload
        .country
        .map(|v| v.trim().to_uppercase())
        .filter(|v| v.len() == 2)
        .unwrap_or_else(|| "US".to_string());

    let credential_id = Uuid::new_v4();
    let plain_token = format!("sk_live_{}_{}", account.client_id.simple(), credential_id.simple());
    let key_hash = Authenticator::hash_key(&plain_token);

    sqlx::query(
        "INSERT INTO api_keys (key_hash, client_id, credential_id, label, rate_limit_req_sec, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())"
    )
    .bind(&key_hash)
    .bind(account.client_id)
    .bind(credential_id)
    .bind(&label)
    .bind(100)
    .execute(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let created_at = chrono::Utc::now().to_rfc3339();

    Ok(Json(BusinessTokenResponse {
        credential_id: credential_id.to_string(),
        token: plain_token,
        username: derive_username(&country, credential_id),
        proxy_host: state.vpn_public_host.clone(),
        proxy_port: state.socks5_port,
        created_at,
        label,
    }))
}

pub async fn list_business_api_tokens(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<BusinessTokenListResponse>, AppError> {
    let account = require_business_session(&state, &headers).await?;

    let rows = sqlx::query(
        "SELECT credential_id, created_at, label
         FROM api_keys
         WHERE client_id = $1
         ORDER BY created_at DESC"
    )
    .bind(account.client_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let tokens = rows
        .into_iter()
        .map(|r| {
            let cid: Uuid = r.get("credential_id");
            let created_at: chrono::DateTime<chrono::Utc> = r.get("created_at");
            let label: Option<String> = r.get("label");
            BusinessTokenListItem {
                credential_id: cid.to_string(),
                username: derive_username("US", cid),
                created_at: created_at.to_rfc3339(),
                label,
            }
        })
        .collect();

    Ok(Json(BusinessTokenListResponse { tokens }))
}

pub async fn revoke_business_api_token(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(credential_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let account = require_business_session(&state, &headers).await?;

    let result = sqlx::query(
        "DELETE FROM api_keys WHERE client_id = $1 AND credential_id = $2"
    )
    .bind(account.client_id)
    .bind(credential_id)
    .execute(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    if result.rows_affected() == 0 {
        return Err(AppError::BadRequest("token not found".to_string()));
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn get_business_session_me(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, AppError> {
    let account = require_business_session(&state, &headers).await?;

    Ok(Json(serde_json::json!({
        "account_id": account.account_id,
        "client_id": account.client_id,
        "company_name": account.company_name,
        "email": account.email,
    })))
}
