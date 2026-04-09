use crate::error::AppError;
use crate::state::AppState;
use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;
use tracing::info;
use uuid::Uuid;

const FREE_DAILY_LIMIT_BYTES: i64 = 1_073_741_824;

fn is_paid_tier(balance: f64, reward_unlimited_until: Option<chrono::DateTime<chrono::Utc>>, node_active: bool) -> bool {
    let reward_active = reward_unlimited_until
        .map(|until| until > chrono::Utc::now())
        .unwrap_or(false);
    balance >= 1.0 || reward_active || node_active
}

async fn ensure_client_row_for_mobile_node(
    state: &Arc<AppState>,
    client_id: Uuid,
) -> Result<(), AppError> {
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM mobile_nodes WHERE id = $1)")
        .bind(client_id)
        .fetch_one(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    if !exists {
        return Err(AppError::Unauthorized);
    }

    sqlx::query(
        "INSERT INTO clients (id, email, balance_usd) VALUES ($1, $2, 0.0) ON CONFLICT DO NOTHING"
    )
    .bind(client_id)
    .bind(format!("{}@byteaway.internal", client_id))
    .execute(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    Ok(())
}

/// Request from VPN gateway to report traffic stats
#[derive(Deserialize)]
pub struct VpnTrafficReport {
    pub client_id: Uuid,
    pub gateway_id: String,
    pub bytes_upload: u64,
    pub bytes_download: u64,
}

/// Response after processing traffic report
#[derive(Serialize)]
pub struct VpnTrafficResponse {
    pub success: bool,
    pub billed_usd: f64,
    pub remaining_balance: f64,
}

/// POST /api/v1/vpn/traffic-report
/// Called by VPN gateway instances to report client traffic and deduct balance
pub async fn report_vpn_traffic(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<VpnTrafficReport>,
) -> Result<Json<VpnTrafficResponse>, AppError> {
    // Calculate cost based on total bytes
    let total_bytes = payload.bytes_upload + payload.bytes_download;
    let gb = total_bytes as f64 / 1_073_741_824.0;
    let cost = gb * state.price_per_gb_usd;

    // Get current client financial/reward state
    let row = sqlx::query(
        "SELECT balance_usd::float8 as balance, reward_unlimited_until FROM clients WHERE id = $1"
    )
        .bind(payload.client_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    let (current_balance, reward_unlimited_until): (f64, Option<chrono::DateTime<chrono::Utc>>) = match row {
        Some(r) => (r.get("balance"), r.get("reward_unlimited_until")),
        None => {
            ensure_client_row_for_mobile_node(&state, payload.client_id).await?;
            (0.0, None)
        }
    };

    let node_active = state.registry.active_connections.contains_key(&payload.client_id);
    let is_paid = is_paid_tier(current_balance, reward_unlimited_until, node_active);

    if !is_paid {
        let used_today: i64 = sqlx::query_scalar(
            "SELECT COALESCE(bytes_used, 0) FROM client_daily_traffic WHERE client_id = $1 AND traffic_date = CURRENT_DATE"
        )
        .bind(payload.client_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(AppError::Database)?
        .unwrap_or(0);

        let next_used = used_today.saturating_add(total_bytes as i64);
        if next_used > FREE_DAILY_LIMIT_BYTES {
            info!(
                "Free daily quota exceeded for client {}: used={} + report={} > limit={}",
                payload.client_id,
                used_today,
                total_bytes,
                FREE_DAILY_LIMIT_BYTES
            );

            sqlx::query(
                "UPDATE vpn_sessions
                 SET is_active = FALSE, ended_at = NOW(),
                     bytes_upload = $2, bytes_download = $3
                 WHERE client_id = $1 AND vpn_gateway_id = $4 AND is_active = TRUE"
            )
            .bind(payload.client_id)
            .bind(payload.bytes_upload as i64)
            .bind(payload.bytes_download as i64)
            .bind(&payload.gateway_id)
            .execute(&state.db_pool)
            .await
            .map_err(AppError::Database)?;

            return Ok(Json(VpnTrafficResponse {
                success: false,
                billed_usd: 0.0,
                remaining_balance: current_balance,
            }));
        }

        sqlx::query(
            "INSERT INTO client_daily_traffic (client_id, traffic_date, bytes_used)
             VALUES ($1, CURRENT_DATE, $2)
             ON CONFLICT (client_id, traffic_date)
             DO UPDATE SET bytes_used = client_daily_traffic.bytes_used + EXCLUDED.bytes_used"
        )
        .bind(payload.client_id)
        .bind(total_bytes as i64)
        .execute(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

        info!(
            "VPN free traffic recorded: client={}, upload={}, download={}, daily_used={}B",
            payload.client_id,
            payload.bytes_upload,
            payload.bytes_download,
            next_used
        );

        return Ok(Json(VpnTrafficResponse {
            success: true,
            billed_usd: 0.0,
            remaining_balance: current_balance,
        }));
    }

    // Check if client has sufficient balance
    if current_balance < cost {
        // Insufficient balance - mark session for termination
        info!(
            "VPN client {} has insufficient balance: ${:.4} available, ${:.4} required",
            payload.client_id, current_balance, cost
        );
        
        // Update session to mark it should be terminated
        sqlx::query(
            "UPDATE vpn_sessions 
             SET is_active = FALSE, ended_at = NOW(), 
                 bytes_upload = $2, bytes_download = $3, billed_usd = $4
             WHERE client_id = $1 AND vpn_gateway_id = $5 AND is_active = TRUE"
        )
        .bind(payload.client_id)
        .bind(payload.bytes_upload as i64)
        .bind(payload.bytes_download as i64)
        .bind(cost)
        .bind(&payload.gateway_id)
        .execute(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

        return Ok(Json(VpnTrafficResponse {
            success: false,
            billed_usd: 0.0,
            remaining_balance: current_balance,
        }));
    }

    // Deduct balance and update session
    let new_balance = current_balance - cost;
    
    let result = sqlx::query(
        "UPDATE clients SET balance_usd = balance_usd - $1 WHERE id = $2 AND balance_usd >= $1"
    )
    .bind(cost)
    .bind(payload.client_id)
    .execute(&state.db_pool)
    .await;

    match result {
        Ok(r) if r.rows_affected() > 0 => {
            // Update session stats
            sqlx::query(
                "UPDATE vpn_sessions 
                 SET bytes_upload = $2, bytes_download = $3, billed_usd = billed_usd + $4 
                  WHERE client_id = $1 AND vpn_gateway_id = $5 AND is_active = TRUE"
            )
            .bind(payload.client_id)
            .bind(payload.bytes_upload as i64)
            .bind(payload.bytes_download as i64)
            .bind(cost)
              .bind(&payload.gateway_id)
            .execute(&state.db_pool)
            .await
            .map_err(AppError::Database)?;

            info!(
                "VPN traffic billed: client={}, upload={}, download={}, cost=${:.4}, remaining=${:.4}",
                payload.client_id, payload.bytes_upload, payload.bytes_download, cost, new_balance
            );

            Ok(Json(VpnTrafficResponse {
                success: true,
                billed_usd: cost,
                remaining_balance: new_balance,
            }))
        }
        _ => {
            Err(AppError::InsufficientBalance)
        }
    }
}

/// Request to check if client should be disconnected
#[derive(Deserialize)]
pub struct VpnCheckRequest {
    pub client_id: Uuid,
    pub gateway_id: String,
}

#[derive(Serialize)]
pub struct VpnCheckResponse {
    pub should_terminate: bool,
    pub reason: Option<String>,
}

/// GET /api/v1/vpn/check-client?client_id=...&gateway_id=...
/// Called by VPN gateway to check if client session should be terminated
pub async fn check_client_session(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(payload): axum::extract::Query<VpnCheckRequest>,
) -> Result<Json<VpnCheckResponse>, AppError> {
    // Check if session is still active
    let row = sqlx::query(
        "SELECT is_active FROM vpn_sessions WHERE client_id = $1 AND vpn_gateway_id = $2"
    )
    .bind(payload.client_id)
    .bind(&payload.gateway_id)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(AppError::Database)?;

    let is_active: bool = match row {
        Some(r) => r.get("is_active"),
        None => false,
    };

    // Also check balance and tier status
    let balance_row = sqlx::query(
        "SELECT balance_usd::float8 as balance, reward_unlimited_until FROM clients WHERE id = $1"
    )
        .bind(payload.client_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(AppError::Database)?;

    let (balance, reward_unlimited_until): (f64, Option<chrono::DateTime<chrono::Utc>>) = if let Some(r) = balance_row {
        (r.get::<f64, _>("balance"), r.get("reward_unlimited_until"))
    } else {
        ensure_client_row_for_mobile_node(&state, payload.client_id).await?;
        (0.0, None)
    };

    let node_active = state.registry.active_connections.contains_key(&payload.client_id);
    let paid = is_paid_tier(balance, reward_unlimited_until, node_active);

    // Free-tier users: check daily limit instead of balance
    let should_terminate = if !is_active {
        true
    } else if paid {
        false
    } else {
        // Free tier: check if daily quota exceeded
        let used_today: i64 = sqlx::query_scalar(
            "SELECT COALESCE(bytes_used, 0) FROM client_daily_traffic WHERE client_id = $1 AND traffic_date = CURRENT_DATE"
        )
        .bind(payload.client_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(AppError::Database)?
        .unwrap_or(0);

        used_today >= FREE_DAILY_LIMIT_BYTES
    };

    let reason = if !is_active {
        Some("Session inactive".to_string())
    } else if should_terminate {
        Some("Daily free quota exceeded".to_string())
    } else {
        None
    };

    Ok(Json(VpnCheckResponse {
        should_terminate,
        reason,
    }))
}
