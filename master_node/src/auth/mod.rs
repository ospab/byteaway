pub mod middleware;

use crate::error::AppError;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::Row;
use tracing::debug;

/// Контекст аутентифицированного B2B клиента
#[derive(Clone, Debug)]
pub struct AuthContext {
    pub client_id: uuid::Uuid,
    #[allow(dead_code)]
    pub available_balance_usd: f64,
}

#[derive(Serialize, Deserialize)]
struct CachedAuth {
    client_id: uuid::Uuid,
    balance_usd: f64,
}

/// Аутентификатор API-ключей: Redis cache → PostgreSQL fallback
pub struct Authenticator {
    pub db_pool: sqlx::PgPool,
    pub redis_client: redis::Client,
}

impl Authenticator {
    pub fn new(db_pool: sqlx::PgPool, redis_client: redis::Client) -> Self {
        Self { db_pool, redis_client }
    }

    /// SHA-256 хеш API-ключа (хранится в БД вместо plain-text)
    pub fn hash_key(api_key: &str) -> String {
        let digest = Sha256::digest(api_key.as_bytes());
        hex::encode(digest)
    }

    /// Проверяет API-ключ. Сначала Redis кеш, затем Postgres.
    /// Включает защиту от брутфорса по IP.
    pub async fn authenticate(&self, api_key: &str, client_ip: &str) -> Result<AuthContext, AppError> {
        // 0. Защита от брутфорса
        self.check_brute_force(client_ip, api_key).await?;

        let res = self.do_authenticate(api_key).await;

        if res.is_err() {
            self.record_auth_failure(client_ip, api_key).await?;
        } else {
            self.clear_auth_failures(client_ip, api_key).await?;
        }

        res
    }

    async fn do_authenticate(&self, api_key: &str) -> Result<AuthContext, AppError> {
        let api_key = api_key.trim_matches(|c: char| c.is_whitespace() || c == '\0');
        let key_hash = Self::hash_key(api_key);
        debug!("Checking key_hash: {}", key_hash);
        let cache_key = format!("auth:cache:{}", key_hash);

        // 1. Проверяем Redis кеш
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(AppError::Redis)?;

        let cached: Option<String> = conn.get(&cache_key).await.map_err(AppError::Redis)?;
        if let Some(json) = cached {
            if let Ok(c) = serde_json::from_str::<CachedAuth>(&json) {
                debug!("Auth cache hit for key_hash={}", &key_hash[..8]);
                return Ok(AuthContext {
                    client_id: c.client_id,
                    available_balance_usd: c.balance_usd,
                });
            }
        }

        // 2. Фоллбек в PostgreSQL
        let row = sqlx::query(
            "SELECT c.id, c.balance_usd::float8 as balance \
             FROM clients c \
             JOIN api_keys ak ON ak.client_id = c.id \
             WHERE ak.key_hash = $1",
        )
        .bind(&key_hash)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(AppError::Database)?;

        if let Some(r) = row {
            let client_id: uuid::Uuid = r.get("id");
            let balance: f64 = r.get("balance");

            let cached = CachedAuth { client_id, balance_usd: balance };
            let json = serde_json::to_string(&cached).unwrap_or_default();
            let _: () = conn.set_ex(&cache_key, json, 60).await.map_err(AppError::Redis)?;

            return Ok(AuthContext {
                client_id,
                available_balance_usd: balance,
            });
        }

        // 3. Проверяем B2C Device ID
        let node_row = sqlx::query(
            "SELECT id FROM mobile_nodes WHERE device_id = $1",
        )
        .bind(api_key)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(AppError::Database)?;

        if let Some(r) = node_row {
            let node_id: uuid::Uuid = r.get("id");
            return Ok(AuthContext {
                client_id: node_id,
                available_balance_usd: 1000.0,
            });
        }

        // 3b. Проверяем B2C токен как mobile_nodes.id (server-issued token)
        if let Ok(node_uuid) = uuid::Uuid::parse_str(api_key) {
            let by_id = sqlx::query(
                "SELECT id FROM mobile_nodes WHERE id = $1",
            )
            .bind(node_uuid)
            .fetch_optional(&self.db_pool)
            .await
            .map_err(AppError::Database)?;

            if by_id.is_some() {
                return Ok(AuthContext {
                    client_id: node_uuid,
                    available_balance_usd: 1000.0,
                });
            }
        }

        // 4. Автопровижининг B2C
        if let Ok(device_uuid) = uuid::Uuid::parse_str(api_key) {
            let mut tx = self.db_pool.begin().await.map_err(AppError::Database)?;

            let node_id: uuid::Uuid = sqlx::query_scalar(
                "INSERT INTO mobile_nodes (id, device_id) \
                 VALUES ($1, $2) \
                 ON CONFLICT (device_id) DO UPDATE SET registered_at = NOW() \
                 RETURNING id",
            )
            .bind(device_uuid)
            .bind(api_key)
            .fetch_one(&mut *tx)
            .await
            .map_err(AppError::Database)?;

            sqlx::query(
                "INSERT INTO clients (id, email, balance_usd) \
                 VALUES ($1, $2, 0.0) \
                 ON CONFLICT DO NOTHING",
            )
            .bind(node_id)
            .bind(format!("{}@byteaway.internal", api_key))
            .execute(&mut *tx)
            .await
            .map_err(AppError::Database)?;

            tx.commit().await.map_err(AppError::Database)?;

            debug!("Auto-provisioned B2C node for device_id={}", api_key);
            return Ok(AuthContext {
                client_id: node_id,
                available_balance_usd: 1000.0,
            });
        }

        Err(AppError::Unauthorized)
    }

    fn brute_force_scope(ip: &str, api_key: &str) -> String {
        // Scope by IP + key fingerprint to avoid blocking all users behind shared NAT.
        format!("{}:{}", ip, Self::hash_key(api_key))
    }

    /// Проверяет, не заблокирован ли IP+ключ за перебор
    async fn check_brute_force(&self, ip: &str, api_key: &str) -> Result<(), AppError> {
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(AppError::Redis)?;

        let scope = Self::brute_force_scope(ip, api_key);
        let ban_key = format!("auth:ban:{}", scope);
        let banned: Option<bool> = conn.get(&ban_key).await.map_err(AppError::Redis)?;

        if banned.unwrap_or(false) {
            tracing::warn!("Blocked request from banned scope: ip={}", ip);
            return Err(AppError::Unauthorized);
        }

        Ok(())
    }

    /// Записывает неудачную попытку и банит при превышении (5 попыток) в рамках IP+ключ.
    async fn record_auth_failure(&self, ip: &str, api_key: &str) -> Result<(), AppError> {
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(AppError::Redis)?;

        let scope = Self::brute_force_scope(ip, api_key);
        let fail_key = format!("auth:fails:{}", scope);
        let fails: u32 = conn.incr(&fail_key, 1).await.map_err(AppError::Redis)?;

        // Устанавливаем TTL для счетчика неудач (15 минут)
        let _: () = conn.expire(&fail_key, 900).await.map_err(AppError::Redis)?;

        if fails >= 5 {
            tracing::error!("IP {} key-scope banned for 10 minutes due to multiple auth failures", ip);
            let ban_key = format!("auth:ban:{}", scope);
            let _: () = conn.set_ex(&ban_key, true, 600).await.map_err(AppError::Redis)?;
            let _: () = conn.del(&fail_key).await.map_err(AppError::Redis)?;
        }

        Ok(())
    }

    async fn clear_auth_failures(&self, ip: &str, api_key: &str) -> Result<(), AppError> {
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(AppError::Redis)?;

        let scope = Self::brute_force_scope(ip, api_key);
        let fail_key = format!("auth:fails:{}", scope);
        let _: () = conn.del(&fail_key).await.map_err(AppError::Redis)?;
        Ok(())
    }
}
