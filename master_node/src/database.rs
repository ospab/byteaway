use sqlx::PgPool;
use std::time::Duration;
use tracing::{info, error};

#[allow(dead_code)]
pub struct DatabaseManager {
    pool: PgPool,
}

#[allow(dead_code)]
impl DatabaseManager {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Optimized query with connection pooling and timeout
    pub async fn execute_with_timeout<T, F>(
        &self,
        operation: F,
        timeout_secs: u64,
    ) -> Result<T, sqlx::Error>
    where
        F: std::future::Future<Output = Result<T, sqlx::Error>>,
    {
        tokio::time::timeout(Duration::from_secs(timeout_secs), operation).await
            .map_err(|_| {
                error!("Database operation timed out after {} seconds", timeout_secs);
                sqlx::Error::Io(std::io::Error::new(
                    std::io::ErrorKind::TimedOut,
                    "Database operation timed out",
                ))
            })?
    }

    /// Batch insert for better performance
    pub async fn batch_insert_usage_records(
        &self,
        records: Vec<(uuid::Uuid, i64, chrono::DateTime<chrono::Utc>)>,
    ) -> Result<(), sqlx::Error> {
        if records.is_empty() {
            return Ok(());
        }

        let records_count = records.len();
        let mut tx = self.pool.begin().await?;
        
        let query = "
            INSERT INTO usage_logs (client_id, bytes_used, timestamp)
            VALUES ($1, $2, $3)
            ON CONFLICT (client_id, timestamp) 
            DO UPDATE SET bytes_used = usage_logs.bytes_used + EXCLUDED.bytes_used
        ";

        for (client_id, bytes, timestamp) in records {
            sqlx::query(query)
                .bind(client_id)
                .bind(bytes)
                .bind(timestamp)
                .execute(&mut *tx)
                .await?;
        }

        tx.commit().await?;
        info!("Batch inserted {} usage records", records_count);
        Ok(())
    }

    /// Get client usage with caching hints
    pub async fn get_client_usage(
        &self,
        client_id: uuid::Uuid,
        from_date: chrono::DateTime<chrono::Utc>,
    ) -> Result<i64, sqlx::Error> {
        let query = "
            SELECT COALESCE(SUM(bytes_used), 0) as total_bytes
            FROM usage_logs 
            WHERE client_id = $1 AND timestamp >= $2
        ";

        let result: Option<i64> = sqlx::query_scalar(query)
            .bind(client_id)
            .bind(from_date)
            .fetch_optional(&self.pool)
            .await?;

        Ok(result.unwrap_or(0))
    }

    /// Update client balance with optimistic locking
    pub async fn update_client_balance(
        &self,
        client_id: uuid::Uuid,
        amount: f64,
        expected_version: i32,
    ) -> Result<bool, sqlx::Error> {
        let query = "
            UPDATE clients 
            SET balance = balance + $1, version = version + 1
            WHERE id = $2 AND version = $3
        ";

        let result = sqlx::query(query)
            .bind(amount)
            .bind(client_id)
            .bind(expected_version)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Health check with connection validation
    pub async fn health_check(&self) -> Result<(), sqlx::Error> {
        self.execute_with_timeout(
            async {
                sqlx::query("SELECT 1")
                    .fetch_one(&self.pool)
                    .await
                    .map(|_| ())
            },
            5,
        ).await
    }

    /// Get connection pool statistics
    pub async fn pool_stats(&self) -> PoolStats {
        let pool_size = self.pool.size();
        let num_idle = self.pool.num_idle();
        
        PoolStats {
            total_connections: pool_size,
            idle_connections: num_idle as u32,
            active_connections: pool_size.saturating_sub(num_idle as u32),
        }
    }

    /// Cleanup old records with batch processing
    pub async fn cleanup_old_records(
        &self,
        days_to_keep: i32,
        batch_size: usize,
    ) -> Result<usize, sqlx::Error> {
        let cutoff_date = chrono::Utc::now() - chrono::Duration::days(days_to_keep as i64);
        let mut total_deleted: u64 = 0;

        loop {
            let result = sqlx::query(
                "DELETE FROM usage_logs 
                 WHERE timestamp < $1 
                 LIMIT $2"
            )
            .bind(cutoff_date)
            .bind(batch_size as i64)
            .execute(&self.pool)
            .await?;

            let deleted = result.rows_affected();
            total_deleted += deleted;

            if deleted < batch_size as u64 {
                break;
            }

            // Small delay to prevent overwhelming the database
            tokio::time::sleep(Duration::from_millis(10)).await;
        }

        info!("Cleaned up {} old usage records", total_deleted);
        Ok(total_deleted as usize)
    }
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct PoolStats {
    pub total_connections: u32,
    pub idle_connections: u32,
    pub active_connections: u32,
}

/// Database connection pool configuration
#[allow(dead_code)]
pub struct PoolConfig {
    pub max_connections: u32,
    pub min_connections: u32,
    pub connection_timeout: Duration,
    pub idle_timeout: Duration,
    pub max_lifetime: Duration,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections: 50,
            min_connections: 5,
            connection_timeout: Duration::from_secs(30),
            idle_timeout: Duration::from_secs(600),
            max_lifetime: Duration::from_secs(1800),
        }
    }
}

/// Create optimized database pool
#[allow(dead_code)]
pub async fn create_pool(
    database_url: &str,
    config: PoolConfig,
) -> Result<PgPool, sqlx::Error> {
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(config.max_connections)
        .min_connections(config.min_connections)
        .acquire_timeout(config.connection_timeout)
        .idle_timeout(config.idle_timeout)
        .max_lifetime(config.max_lifetime)
        .connect(database_url)
        .await?;

    info!("Database pool created with {} max connections", config.max_connections);
    Ok(pool)
}
