use crate::error::AppError;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use tracing::info;
use uuid::Uuid;

/// VPN Gateway information for load balancing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VpnGateway {
    pub id: String,
    pub public_host: String,
    pub public_port: u16,
    pub region: Option<String>,
    pub max_clients: i32,
    pub current_clients: i32,
    pub is_healthy: bool,
    pub reality_public_key: String,
    pub reality_short_id: String,
}

/// Manages VPN gateway registry and client assignment
pub struct VpnGatewayRegistry {
    #[allow(dead_code)]
    redis_client: redis::Client,
    #[allow(dead_code)]
    db_pool: sqlx::PgPool,
    #[allow(dead_code)]
    default_gateway: VpnGateway,
}

impl VpnGatewayRegistry {
    #[allow(dead_code)]
    pub fn new(redis_url: &str, db_pool: sqlx::PgPool, default_gateway: VpnGateway) -> Result<Self, AppError> {
        let client = redis::Client::open(redis_url).map_err(AppError::Redis)?;
        Ok(Self {
            redis_client: client,
            db_pool,
            default_gateway,
        })
    }

    /// Find the least loaded healthy gateway
    #[allow(dead_code)]
    pub async fn select_gateway(&self) -> Result<VpnGateway, AppError> {
        // Try to get from DB first for multi-instance setup

        let row = sqlx::query(
            "SELECT id, public_host, public_port, region, max_clients, current_clients, 
                    is_healthy, reality_public_key, reality_short_id 
             FROM vpn_gateways 
             WHERE is_healthy = TRUE AND current_clients < max_clients 
             ORDER BY current_clients ASC 
             LIMIT 1"
        )
        .fetch_optional(&self.db_pool)
        .await
        .map_err(AppError::Database)?;

        if let Some(r) = row {
            return Ok(VpnGateway {
                id: r.get("id"),
                public_host: r.get("public_host"),
                public_port: r.get::<i32, _>("public_port") as u16,
                region: r.get("region"),
                max_clients: r.get("max_clients"),
                current_clients: r.get("current_clients"),
                is_healthy: r.get("is_healthy"),
                reality_public_key: r.get("reality_public_key"),
                reality_short_id: r.get("reality_short_id"),
            });
        }

        // Fallback to default gateway (single instance)
        Ok(self.default_gateway.clone())
    }

    /// Assign IP and track session start
    #[allow(dead_code)]
    pub async fn assign_session(&self, client_id: Uuid, gateway_id: &str) -> Result<String, AppError> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await.map_err(AppError::Redis)?;
        
        // Generate IP from pool (10.8.0.0/24)
        let assigned_key = format!("vpn:assigned_ip:{}", client_id);
        let existing: Option<String> = conn.get(&assigned_key).await.map_err(AppError::Redis)?;
        
        let assigned_ip = if let Some(ip) = existing {
            ip
        } else {
            let next: i64 = conn.incr("vpn:ip:next", 1).await.map_err(AppError::Redis)?;
            let host = 2 + ((next - 1) % 250); // .2 to .251
            let ip = format!("10.8.0.{}", host);
            conn.set_ex::<_, _, ()>(&assigned_key, &ip, 86400).await.map_err(AppError::Redis)?;
            ip
        };

        // Insert session record
        sqlx::query(
            "INSERT INTO vpn_sessions (client_id, assigned_ip, vpn_gateway_id, started_at, is_active) 
             VALUES ($1, $2, $3, NOW(), TRUE)
             ON CONFLICT (client_id) 
             DO UPDATE SET assigned_ip = EXCLUDED.assigned_ip, vpn_gateway_id = EXCLUDED.vpn_gateway_id, 
                          started_at = EXCLUDED.started_at, is_active = TRUE
             WHERE vpn_sessions.is_active = FALSE"
        )
        .bind(client_id)
        .bind(&assigned_ip)
        .bind(gateway_id)
        .execute(&self.db_pool)
        .await
        .map_err(AppError::Database)?;

        // Increment gateway client count
        sqlx::query("UPDATE vpn_gateways SET current_clients = current_clients + 1 WHERE id = $1")
            .bind(gateway_id)
            .execute(&self.db_pool)
            .await
            .map_err(AppError::Database)?;

        info!("VPN session assigned: client={}, ip={}, gateway={}", client_id, assigned_ip, gateway_id);
        Ok(assigned_ip)
    }

    /// End session and update stats
    #[allow(dead_code)]
    pub async fn end_session(&self, client_id: Uuid, bytes_upload: u64, bytes_download: u64, cost_usd: f64) -> Result<(), AppError> {
        let gateway_id: Option<String> = sqlx::query(
            "UPDATE vpn_sessions \
             SET is_active = FALSE, ended_at = NOW(), \
                 bytes_upload = $2, bytes_download = $3, billed_usd = $4
             WHERE client_id = $1 AND is_active = TRUE \
             RETURNING vpn_gateway_id"
        )
        .bind(client_id)
        .bind(bytes_upload as i64)
        .bind(bytes_download as i64)
        .bind(cost_usd)
        .fetch_optional(&self.db_pool)
        .await
        .map(|row_opt| row_opt.map(|row| row.get::<String, _>("vpn_gateway_id")))
        .map_err(AppError::Database)?;

        // Decrement gateway load counter so new clients can be admitted
        if let Some(gateway_id) = gateway_id {
            sqlx::query(
                "UPDATE vpn_gateways \
                 SET current_clients = GREATEST(current_clients - 1, 0) \
                 WHERE id = $1"
            )
            .bind(&gateway_id)
            .execute(&self.db_pool)
            .await
            .map_err(AppError::Database)?;
        }

        // Clean up Redis
        let mut conn = self.redis_client.get_multiplexed_async_connection().await.map_err(AppError::Redis)?;
        let _: () = conn.del(format!("vpn:assigned_ip:{}", client_id)).await.unwrap_or_default();

        info!("VPN session ended: client={}, upload={}, download={}, cost=${:.4}", 
              client_id, bytes_upload, bytes_download, cost_usd);
        Ok(())
    }

    /// Check if client has active session
    #[allow(dead_code)]
    pub async fn has_active_session(&self, client_id: Uuid) -> Result<bool, AppError> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM vpn_sessions WHERE client_id = $1 AND is_active = TRUE"
        )
        .bind(client_id)
        .fetch_one(&self.db_pool)
        .await
        .map_err(AppError::Database)?;
        
        Ok(count > 0)
    }

    /// Get session stats for billing
    #[allow(dead_code)]
    pub async fn get_session_stats(&self, client_id: Uuid) -> Result<(u64, u64), AppError> {
        let row = sqlx::query(
            "SELECT COALESCE(bytes_upload, 0) as up, COALESCE(bytes_download, 0) as down 
             FROM vpn_sessions WHERE client_id = $1 AND is_active = TRUE"
        )
        .bind(client_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(AppError::Database)?;

        if let Some(r) = row {
            let up: i64 = r.get("up");
            let down: i64 = r.get("down");
            return Ok((up as u64, down as u64));
        }
        Ok((0, 0))
    }

    /// Update session traffic counters (called by gateway metrics)
    #[allow(dead_code)]
    pub async fn update_traffic(&self, client_id: Uuid, bytes_upload: u64, bytes_download: u64) -> Result<(), AppError> {
        sqlx::query(
            "UPDATE vpn_sessions 
             SET bytes_upload = $2, bytes_download = $3 
             WHERE client_id = $1 AND is_active = TRUE"
        )
        .bind(client_id)
        .bind(bytes_upload as i64)
        .bind(bytes_download as i64)
        .execute(&self.db_pool)
        .await
        .map_err(AppError::Database)?;
        Ok(())
    }

    /// Gateway heartbeat (called by sing-box instances)
    #[allow(dead_code)]
    pub async fn gateway_heartbeat(&self, gateway_id: &str) -> Result<(), AppError> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await.map_err(AppError::Redis)?;
        
        let key = format!("vpn:gateway:heartbeat:{}", gateway_id);
        conn.set_ex::<_, _, ()>(&key, "alive", 60).await.map_err(AppError::Redis)?;
        
        // Also update DB
        sqlx::query("UPDATE vpn_gateways SET last_heartbeat = NOW(), is_healthy = TRUE WHERE id = $1")
            .bind(gateway_id)
            .execute(&self.db_pool)
            .await
            .map_err(AppError::Database)?;
        
        Ok(())
    }
}
