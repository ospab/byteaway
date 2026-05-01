use super::BillingEngine;
use crate::error::AppError;
use redis::AsyncCommands;
use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

const REWARD_DAY_BYTES: i64 = 200 * 1024 * 1024;

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
        if bytes == 0 {
            return Ok(());
        }
        
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(AppError::Redis)?;

        let pair_key = format!("traffic:pair:{}:{}", client_id, node_id);
        let pair_id = format!("{}:{}", client_id, node_id);

        tracing::info!("[BILLING] commit_usage: client={} node={} bytes={}", client_id, node_id, bytes);

        let _: () = redis::pipe()
            .atomic()
            .cmd("INCRBY").arg(&pair_key).arg(bytes)
            .cmd("SADD").arg("traffic:active_pairs").arg(pair_id)
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

        // Берём список активных пар {client_id}:{node_id}
        let pair_ids: Vec<String> = conn
            .smembers("traffic:active_pairs")
            .await
            .map_err(AppError::Redis)?;

        for pair_id in pair_ids {
            let parts: Vec<&str> = pair_id.split(':').collect();
            if parts.len() != 2 { continue; }

            let client_id = match Uuid::parse_str(parts[0]) {
                Ok(id) => id,
                Err(_) => continue,
            };
            let node_id = match Uuid::parse_str(parts[1]) {
                Ok(id) => id,
                Err(_) => continue,
            };

            let pair_key = format!("traffic:pair:{}:{}", client_id, node_id);

            // Атомарно забираем и обнуляем счётчик
            let bytes: Option<u64> = redis::cmd("GETDEL")
                .arg(&pair_key)
                .query_async(&mut conn)
                .await
                .map_err(AppError::Redis)?;

            let bytes = match bytes {
                Some(b) if b > 0 => b,
                _ => {
                    let _: () = conn.srem("traffic:active_pairs", &pair_id)
                        .await
                        .unwrap_or_default();
                    continue;
                }
            };

            let gb = bytes as f64 / 1_073_741_824.0;
            let cost = gb * self.price_per_gb_usd;

            // 1. Списываем доступный баланс (partial charge), чтобы трафик не терялся в статистике.
            let current_balance: f64 = sqlx::query_scalar(
                "SELECT balance_usd::float8 FROM clients WHERE id = $1"
            )
            .bind(client_id)
            .fetch_optional(&self.db_pool)
            .await
            .map_err(AppError::Database)?
            .unwrap_or(0.0);

            let billed_usd = current_balance.min(cost);
            if billed_usd > 0.0 {
                let _ = sqlx::query(
                    "UPDATE clients
                     SET balance_usd = GREATEST(balance_usd - $1, 0)
                     WHERE id = $2"
                )
                .bind(billed_usd)
                .bind(client_id)
                .execute(&self.db_pool)
                .await;
            }

            // 2. Начисляем трафик ноде и rewards (даже если billed_usd = 0, трафик был реально прокачан).
            let _ = sqlx::query(
                "UPDATE mobile_nodes SET total_gb_provided = total_gb_provided + $1 WHERE id = $2"
            )
            .bind(gb)
            .bind(node_id)
            .execute(&self.db_pool).await;

            let _ = sqlx::query(
                "UPDATE clients
                 SET reward_shared_bytes_remainder = (reward_shared_bytes_remainder + $1) % $2,
                     reward_pending_days = reward_pending_days + ((reward_shared_bytes_remainder + $1) / $2)::int
                 WHERE id = $3"
            )
            .bind(bytes as i64)
            .bind(REWARD_DAY_BYTES)
            .bind(node_id)
            .execute(&self.db_pool)
            .await;

            // 3. Всегда пишем traffic_history, чтобы мобильная статистика/графики не теряли трафик.
            let _ = sqlx::query(
                "INSERT INTO traffic_history (client_id, node_id, bytes_used, billed_usd, period_start, period_end) \
                 VALUES ($1, $2, $3, $4, NOW() - INTERVAL '1 hour', NOW())"
            )
            .bind(client_id)
            .bind(node_id)
            .bind(bytes as i64)
            .bind(billed_usd)
            .execute(&self.db_pool).await;

            if billed_usd < cost {
                warn!(
                    "Partial billing during flush for client {}: used_bytes={} billed={:.4} requested={:.4}",
                    client_id, bytes, billed_usd, cost
                );
            }

            info!(
                "Flushed {} bytes ({:.4} USD billed) for client {} via node {}",
                bytes, billed_usd, client_id, node_id
            );

            // Убираем из active set
            let _: () = conn.srem("traffic:active_pairs", &pair_id)
                .await
                .unwrap_or_default();
        }

        Ok(())
    }
}
