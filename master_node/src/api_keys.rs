use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc, Duration};
use uuid::Uuid;
use sha2::{Sha256, Digest};
use rand::{distributions::Alphanumeric, Rng};
use std::collections::HashSet;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ApiKey {
    pub id: i32,
    pub key_id: String,
    pub api_key_hash: String,
    pub name: String,
    pub email: Option<String>,
    pub tier: ApiTier,
    pub balance_usd: f64,
    pub traffic_limit_gb: f64,
    pub traffic_used_gb: f64,
    pub max_sessions: i32,
    pub allowed_countries: Option<Vec<String>>,
    pub is_active: bool,
    pub expires_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::Type, sqlx::Decode)]
#[sqlx(type_name = "VARCHAR", rename_all = "lowercase")]
pub enum ApiTier {
    Starter,
    Business,
    Enterprise,
    Custom,
}

impl ApiTier {
    pub fn default_traffic_limit(&self) -> f64 {
        match self {
            ApiTier::Starter => 50.0,
            ApiTier::Business => 250.0,
            ApiTier::Enterprise => 1024.0,
            ApiTier::Custom => 0.0, // Устанавливается индивидуально
        }
    }

    pub fn default_max_sessions(&self) -> i32 {
        match self {
            ApiTier::Starter => 5,
            ApiTier::Business => 20,
            ApiTier::Enterprise => -1, // Безлимит
            ApiTier::Custom => -1,
        }
    }

    pub fn price_per_gb(&self) -> f64 {
        match self {
            ApiTier::Starter => 5.0,
            ApiTier::Business => 4.0,
            ApiTier::Enterprise => 3.0,
            ApiTier::Custom => 2.5,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateApiKeyRequest {
    pub name: String,
    pub email: Option<String>,
    pub tier: ApiTier,
    pub initial_balance_usd: Option<f64>,
    pub traffic_limit_gb: Option<f64>,
    pub max_sessions: Option<i32>,
    pub allowed_countries: Option<Vec<String>>,
    pub expires_days: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiKeyResponse {
    pub key_id: String,
    pub api_key: String, // Только при создании
    pub name: String,
    pub email: Option<String>,
    pub tier: ApiTier,
    pub balance_usd: f64,
    pub traffic_limit_gb: f64,
    pub traffic_used_gb: f64,
    pub traffic_remaining_gb: f64,
    pub max_sessions: i32,
    pub allowed_countries: Option<Vec<String>>,
    pub is_active: bool,
    pub expires_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiKeyUsage {
    pub bytes_transferred: i64,
    pub requests_count: i32,
    pub sessions_count: i32,
    pub countries_used: Vec<String>,
    pub cost_usd: f64,
}

pub struct ApiKeyManager {
    pool: sqlx::PgPool,
}

impl ApiKeyManager {
    pub fn new(pool: sqlx::PgPool) -> Self {
        Self { pool }
    }

    /// Генерирует новый API ключ
    pub fn generate_api_key() -> String {
        let mut rng = rand::thread_rng();
        let random_part: String = rng
            .sample_iter(&Alphanumeric)
            .take(32)
            .map(char::from)
            .collect();
        
        format!("b2b_{}", random_part)
    }

    /// Создает хеш API ключа
    pub fn hash_api_key(api_key: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(api_key.as_bytes());
        format!("{:x}", hasher.finalize())
    }

    /// Создает новый API ключ
    pub async fn create_api_key(
        &self,
        request: CreateApiKeyRequest,
    ) -> Result<ApiKeyResponse, Box<dyn std::error::Error>> {
        let api_key = Self::generate_api_key();
        let key_id = Uuid::new_v4().to_string()[..8].to_string();
        let api_key_hash = Self::hash_api_key(&api_key);

        let traffic_limit = request.traffic_limit_gb.unwrap_or_else(|| request.tier.default_traffic_limit());
        let max_sessions = request.max_sessions.unwrap_or_else(|| request.tier.default_max_sessions());
        let expires_at = request.expires_days.map(|days| Utc::now() + Duration::days(days as i64));

        let api_key_row = sqlx::query_as!(
            ApiKey,
            r#"
            INSERT INTO api_keys (
                key_id, api_key_hash, name, email, tier, 
                balance_usd, traffic_limit_gb, traffic_used_gb, 
                max_sessions, allowed_countries, is_active, 
                expires_at, created_at, updated_at
            ) VALUES (
                $1, $2, $3, $4, $5,
                $6, $7, $8,
                $9, $10, $11,
                $12, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            )
            RETURNING *
            "#,
            key_id,
            api_key_hash,
            request.name,
            request.email,
            request.tier as ApiTier,
            request.initial_balance_usd.unwrap_or(0.0),
            traffic_limit,
            0.0,
            max_sessions,
            request.allowed_countries.as_ref().map(|countries| countries.as_slice()),
            true,
            expires_at,
        )
        .fetch_one(&self.pool)
        .await?;

        Ok(ApiKeyResponse {
            key_id: api_key_row.key_id,
            api_key, // Возвращаем только при создании
            name: api_key_row.name,
            email: api_key_row.email,
            tier: api_key_row.tier,
            balance_usd: api_key_row.balance_usd,
            traffic_limit_gb: api_key_row.traffic_limit_gb,
            traffic_used_gb: api_key_row.traffic_used_gb,
            traffic_remaining_gb: api_key_row.traffic_limit_gb - api_key_row.traffic_used_gb,
            max_sessions: api_key_row.max_sessions,
            allowed_countries: api_key_row.allowed_countries,
            is_active: api_key_row.is_active,
            expires_at: api_key_row.expires_at,
            created_at: api_key_row.created_at,
            last_used_at: api_key_row.last_used_at,
        })
    }

    /// Проверяет валидность API ключа
    pub async fn validate_api_key(&self, api_key: &str) -> Result<Option<ApiKey>, Box<dyn std::error::Error>> {
        let api_key_hash = Self::hash_api_key(api_key);

        let key = sqlx::query_as!(
            ApiKey,
            r#"
            SELECT * FROM api_keys 
            WHERE api_key_hash = $1 AND is_active = true
            AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
            "#,
            api_key_hash
        )
        .fetch_optional(&self.pool)
        .await?;

        // Обновляем last_used_at если ключ найден
        if let Some(ref key) = key {
            sqlx::query!(
                "UPDATE api_keys SET last_used_at = CURRENT_TIMESTAMP WHERE id = $1",
                key.id
            )
            .execute(&self.pool)
            .await?;
        }

        Ok(key)
    }

    /// Получает список всех API ключей (для админа)
    pub async fn list_api_keys(&self) -> Result<Vec<ApiKeyResponse>, Box<dyn std::error::Error>> {
        let keys = sqlx::query_as!(
            ApiKey,
            "SELECT * FROM api_keys ORDER BY created_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;

        let responses: Vec<ApiKeyResponse> = keys
            .into_iter()
            .map(|key| ApiKeyResponse {
                key_id: key.key_id,
                api_key: "".to_string(), // Не возвращаем существующие ключи
                name: key.name,
                email: key.email,
                tier: key.tier,
                balance_usd: key.balance_usd,
                traffic_limit_gb: key.traffic_limit_gb,
                traffic_used_gb: key.traffic_used_gb,
                traffic_remaining_gb: key.traffic_limit_gb - key.traffic_used_gb,
                max_sessions: key.max_sessions,
                allowed_countries: key.allowed_countries,
                is_active: key.is_active,
                expires_at: key.expires_at,
                created_at: key.created_at,
                last_used_at: key.last_used_at,
            })
            .collect();

        Ok(responses)
    }

    /// Обновляет баланс API ключа
    pub async fn update_balance(
        &self,
        key_id: &str,
        amount_usd: f64,
    ) -> Result<(), Box<dyn std::error::Error>> {
        sqlx::query!(
            "UPDATE api_keys SET balance_usd = balance_usd + $1, updated_at = CURRENT_TIMESTAMP WHERE key_id = $2",
            amount_usd,
            key_id
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Добавляет использованный трафик
    pub async fn add_traffic_usage(
        &self,
        key_id: &str,
        bytes_transferred: i64,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let gb_transferred = bytes_transferred as f64 / (1024.0 * 1024.0 * 1024.0);
        
        sqlx::query!(
            "UPDATE api_keys SET traffic_used_gb = traffic_used_gb + $1, updated_at = CURRENT_TIMESTAMP WHERE key_id = $2",
            gb_transferred,
            key_id
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Получает статистику использования за период
    pub async fn get_usage_stats(
        &self,
        key_id: &str,
        start_date: DateTime<Utc>,
        end_date: DateTime<Utc>,
    ) -> Result<ApiKeyUsage, Box<dyn std::error::Error>> {
        let stats = sqlx::query!(
            r#"
            SELECT 
                COALESCE(SUM(bytes_transferred), 0) as bytes_transferred,
                COALESCE(SUM(requests_count), 0) as requests_count,
                COALESCE(SUM(sessions_count), 0) as sessions_count
            FROM usage_stats 
            WHERE api_key_id = (SELECT id FROM api_keys WHERE key_id = $1)
            AND date BETWEEN $2 AND $3
            "#,
            key_id,
            start_date.date_naive(),
            end_date.date_naive()
        )
        .fetch_one(&self.pool)
        .await?;

        let cost_usd = stats.bytes_transferred.unwrap_or(0) as f64 / (1024.0 * 1024.0 * 1024.0) * 5.0; // $5 per GB

        Ok(ApiKeyUsage {
            bytes_transferred: stats.bytes_transferred.unwrap_or(0),
            requests_count: stats.requests_count.unwrap_or(0),
            sessions_count: stats.sessions_count.unwrap_or(0),
            countries_used: vec![], // TODO: Implement countries tracking
            cost_usd,
        })
    }

    /// Блокирует/разблокирует API ключ
    pub async fn toggle_api_key(
        &self,
        key_id: &str,
        is_active: bool,
    ) -> Result<(), Box<dyn std::error::Error>> {
        sqlx::query!(
            "UPDATE api_keys SET is_active = $1, updated_at = CURRENT_TIMESTAMP WHERE key_id = $2",
            is_active,
            key_id
        )
        .execute(&self.pool)
        .await?;

        // Закрываем все активные сессии если блокируем
        if !is_active {
            sqlx::query!(
                "UPDATE api_sessions SET is_active = false WHERE api_key_id = (SELECT id FROM api_keys WHERE key_id = $1)",
                key_id
            )
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    /// Удаляет API ключ
    pub async fn delete_api_key(&self, key_id: &str) -> Result<(), Box<dyn std::error::Error>> {
        sqlx::query!("DELETE FROM api_keys WHERE key_id = $1", key_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }
}
