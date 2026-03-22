use super::BillingEngine;
use crate::error::AppError;
use redis::AsyncCommands;
use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

pub struct DefaultBillingEngine {
    pub db_pool: sqlx::PgPool,
    pub redis_client: redis::Client,
    pub price_per_gb_usd: f64,
}

#[async_trait::async_trait]
impl BillingEngine for DefaultBillingEngine {
    /// Проверяет, что у клиента достаточно средств для предполагаемого объёма трафика
    async fn reserve_balance(&self, client_id: Uuid, est_bytes: u64) -> Result<(), AppError> {
        let est_gb = est_bytes as f64 / 1_073_741_824.0;
        let est_cost = est_gb * self.price_per_gb_usd;

        let row = sqlx::query("SELECT balance_usd::float8 as balance FROM clients WHERE id = $1")
            .bind(client_id)
            .fetch_optional(&self.db_pool)
            .await
            .map_err(AppError::Database)?
            .ok_or(AppError::Unauthorized)?;

        let balance: f64 = row.get("balance");

        if balance < est_cost {
            return Err(AppError::InsufficientBalance);
        }

        Ok(())
    }

    /// Атомарно инкрементирует счётчики трафика в Redis
    async fn commit_usage(&self, client_id: Uuid, node_id: Uuid, bytes: u64) -> Result<(), AppError> {
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(AppError::Redis)?;

        let client_key = format!("traffic:client:{}", client_id);
        let node_key = format!("traffic:node:{}", node_id);

        let _: () = redis::pipe()
            .atomic()
            .cmd("INCRBY").arg(&client_key).arg(bytes)
            .cmd("INCRBY").arg(&node_key).arg(bytes)
            .cmd("SADD").arg("traffic:active_clients").arg(client_id.to_string())
            .query_async(&mut conn)
            .await
            .map_err(AppError::Redis)?;

        Ok(())
    }

    /// Фоновый воркер: забирает накопленные счётчики из Redis,
    /// списывает баланс в Postgres и пишет в traffic_history.
    async fn process_redis_flush(&self) -> Result<(), AppError> {
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(AppError::Redis)?;

        // Берём список клиентов с активным трафиком
        let client_ids: Vec<String> = conn
            .smembers("traffic:active_clients")
            .await
            .map_err(AppError::Redis)?;

        for cid_str in client_ids {
            let client_id = match Uuid::parse_str(&cid_str) {
                Ok(id) => id,
                Err(_) => continue,
            };

            let traffic_key = format!("traffic:client:{}", client_id);

            // Атомарно забираем и обнуляем счётчик
            let bytes: Option<u64> = redis::cmd("GETDEL")
                .arg(&traffic_key)
                .query_async(&mut conn)
                .await
                .map_err(AppError::Redis)?;

            let bytes = match bytes {
                Some(b) if b > 0 => b,
                _ => {
                    let _: () = conn.srem("traffic:active_clients", &cid_str)
                        .await
                        .unwrap_or_default();
                    continue;
                }
            };

            let gb = bytes as f64 / 1_073_741_824.0;
            let cost = gb * self.price_per_gb_usd;

            // Списываем баланс в Postgres
            let result = sqlx::query(
                "UPDATE clients SET balance_usd = balance_usd - $1 WHERE id = $2 AND balance_usd >= $1",
            )
            .bind(cost)
            .bind(client_id)
            .execute(&self.db_pool)
            .await;

            match result {
                Ok(r) if r.rows_affected() > 0 => {
                    info!("Flushed {} bytes ({:.4} USD) for client {}", bytes, cost, client_id);
                }
                Ok(_) => {
                    warn!("Insufficient balance during flush for client {}", client_id);
                }
                Err(e) => {
                    warn!("DB error during flush for client {}: {}", client_id, e);
                }
            }

            // Убираем из active set
            let _: () = conn.srem("traffic:active_clients", &cid_str)
                .await
                .unwrap_or_default();
        }

        Ok(())
    }
}
