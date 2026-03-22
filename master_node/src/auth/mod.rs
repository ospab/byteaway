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
    pub async fn authenticate(&self, api_key: &str) -> Result<AuthContext, AppError> {
        let key_hash = Self::hash_key(api_key);
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

        // 2. Фоллбек в PostgreSQL: Сначала ищем B2B клиента по ключу
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

            // Кешируем в Redis
            let cached = CachedAuth { client_id, balance_usd: balance };
            let json = serde_json::to_string(&cached).unwrap_or_default();
            let _: () = conn.set_ex(&cache_key, json, 60).await.map_err(AppError::Redis)?;

            return Ok(AuthContext {
                client_id,
                available_balance_usd: balance,
            });
        }

        // 3. Если B2B ключ не найден, проверяем, не является ли это B2C Device ID
        // (Для простоты считаем, что B2C ноды имеют фиксированный баланс или бесконечный доступ)
        let node_row = sqlx::query(
            "SELECT id FROM mobile_nodes WHERE device_id = $1",
        )
        .bind(api_key) // Мы передавали device_id как токен в Android приложении
        .fetch_optional(&self.db_pool)
        .await
        .map_err(AppError::Database)?;

        if let Some(r) = node_row {
            let node_id: uuid::Uuid = r.get("id");
            return Ok(AuthContext {
                client_id: node_id,
                available_balance_usd: 1000.0, // Условный безлимит для B2C нод
            });
        }

        Err(AppError::Unauthorized)
    }
}
