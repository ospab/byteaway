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
        let client_uuid = Uuid::new_v4();
        let credential_uuid = Uuid::new_v4();

        let traffic_limit = request.traffic_limit_gb.unwrap_or_else(|| request.tier.default_traffic_limit());
        let max_sessions = request.max_sessions.unwrap_or_else(|| request.tier.default_max_sessions());
        let expires_at = request.expires_days.map(|days| Utc::now() + Duration::days(days as i64));

        // Начинаем транзакцию
        let mut tx = self.pool.begin().await?;

        // 1. Создаем client запись
        sqlx::query(
            "INSERT INTO clients (id, email, balance_usd, created_at) 
             VALUES ($1, $2, $3, NOW()) 
             ON CONFLICT DO NOTHING"
        )
        .bind(client_uuid)
        .bind(request.email.clone().unwrap_or_else(|| format!("{}@byteaway.internal", request.name)))
        .bind(request.initial_balance_usd.unwrap_or(0.0))
        .execute(&mut *tx)
        .await?;

        // 2. Создаем запись в api_keys (старая структура для аутентификатора)
        sqlx::query(
            "INSERT INTO api_keys (key_hash, client_id, credential_id, label, rate_limit_req_sec, created_at)
             VALUES ($1, $2, $3, $4, $5, NOW())"
        )
        .bind(&api_key_hash)
        .bind(client_uuid)
        .bind(credential_uuid)
        .bind(request.name.clone())
        .bind(10i32)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

        // Возвращаем ответ
        Ok(ApiKeyResponse {
            key_id,
            api_key,
            name: request.name,
            email: request.email,
            tier: request.tier,
            balance_usd: request.initial_balance_usd.unwrap_or(0.0),
            traffic_limit_gb: traffic_limit,
            traffic_used_gb: 0.0,
            traffic_remaining_gb: traffic_limit,
            max_sessions,
            allowed_countries: request.allowed_countries,
            is_active: true,
            expires_at,
            created_at: Utc::now(),
            last_used_at: None,
        })
    }

    /// Проверяет валидность API ключа
    pub async fn validate_api_key(&self, api_key: &str) -> Result<Option<ApiKey>, Box<dyn std::error::Error>> {
        let api_key_hash = Self::hash_api_key(api_key);

        // Ищем в правильной таблице api_keys (старая структура с key_hash)
        let row = sqlx::query(
            "SELECT ak.key_hash, ak.client_id, ak.credential_id, ak.label, ak.created_at,
                    c.id as client_id_exists, c.balance_usd 
             FROM api_keys ak 
             JOIN clients c ON c.id = ak.client_id
             WHERE ak.key_hash = $1"
        )
        .bind(&api_key_hash)
        .fetch_optional(&self.pool)
        .await?;

        if row.is_some() {
            // Возвращаем валидный ключ
            Ok(Some(ApiKey {
                id: 0, // Не используется
                key_id: String::new(),
                api_key_hash: api_key_hash.clone(),
                name: row.as_ref().unwrap().get("label").unwrap_or_default(),
                email: None,
                tier: ApiTier::Starter,
                balance_usd: row.as_ref().unwrap().get("balance_usd").unwrap_or(0.0),
                traffic_limit_gb: 50.0,
                traffic_used_gb: 0.0,
                max_sessions: 10,
                allowed_countries: None,
                is_active: true,
                expires_at: None,
                created_at: Utc::now(),
                updated_at: Utc::now(),
                last_used_at: None,
            }))
        } else {
            Ok(None)
        }
    }

    /// Получает список всех API ключей (для админа)
    pub async fn list_api_keys(&self) -> Result<Vec<ApiKeyResponse>, Box<dyn std::error::Error>> {
        // Запрашиваем из обеих таблиц - clients и api_keys
        let rows = sqlx::query(
            "SELECT ak.key_hash, ak.label, ak.created_at, c.balance_usd, c.id as client_id
             FROM api_keys ak 
             JOIN clients c ON c.id = ak.client_id
             ORDER BY ak.created_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;

        let responses: Vec<ApiKeyResponse> = rows
            .into_iter()
            .map(|row| ApiKeyResponse {
                key_id: row.get::<String, _>("key_hash").unwrap_or_default()[..8].to_string(),
                api_key: "".to_string(),
                name: row.get("label").unwrap_or_default(),
                email: None,
                tier: ApiTier::Starter,
                balance_usd: row.get("balance_usd").unwrap_or(0.0),
                traffic_limit_gb: 50.0,
                traffic_used_gb: 0.0,
                traffic_remaining_gb: 50.0,
                max_sessions: 10,
                allowed_countries: None,
                is_active: true,
                expires_at: None,
                created_at: row.get("created_at").unwrap_or_else(|_| Utc::now()),
                last_used_at: None,
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
        // Находим client_id по key_hash и обновляем баланс клиента
        sqlx::query(
            "UPDATE clients SET balance_usd = balance_usd + $1 
             WHERE id = (SELECT client_id FROM api_keys WHERE key_hash = $2)"
        )
        .bind(amount_usd)
        .bind(key_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Добавляет использованный трафик (этот метод не используется напрямую - трафик учитывается через billing engine)
    pub async fn add_traffic_usage(
        &self,
        key_id: &str,
        bytes_transferred: i64,
    ) -> Result<(), Box<dyn std::error::Error>> {
        // Трафик уже учитывается в billing/engine.rs через Redis -> Postgres
        // Этот метод оставлен для совместимости но фактически не нужен
        Ok(())
    }

    /// Получает статистику использования за период
    pub async fn get_usage_stats(
        &self,
        key_id: &str,
        start_date: DateTime<Utc>,
        end_date: DateTime<Utc>,
    ) -> Result<ApiKeyUsage, Box<dyn std::error::Error>> {
        // Получаем client_id по key_hash
        let client_uuid: Option<uuid::Uuid> = sqlx::query_scalar(
            "SELECT client_id FROM api_keys WHERE key_hash = $1"
        )
        .bind(key_id)
        .fetch_optional(&self.pool)
        .await?;

        let client_id = match client_uuid {
            Some(id) => id,
            None => return Ok(ApiKeyUsage {
                bytes_transferred: 0,
                requests_count: 0,
                sessions_count: 0,
                countries_used: vec![],
                cost_usd: 0.0,
            }),
        };

        // Получаем статистику из traffic_history
        let stats = sqlx::query!(
            r#"
            SELECT 
                COALESCE(SUM(bytes_used), 0) as bytes_transferred,
                COUNT(*) as requests_count
            FROM traffic_history 
            WHERE client_id = $1
            AND period_start BETWEEN $2 AND $3
            "#,
            client_id,
            start_date.date_naive(),
            end_date.date_naive()
        )
        .fetch_one(&self.pool)
        .await?;

        let bytes = stats.bytes_transferred.unwrap_or(0);
        let cost_usd = bytes as f64 / (1024.0 * 1024.0 * 1024.0) * 5.0;

        Ok(ApiKeyUsage {
            bytes_transferred: bytes,
            requests_count: stats.requests_count.unwrap_or(0),
            sessions_count: stats.requests_count.unwrap_or(0),
            countries_used: vec![],
            cost_usd,
        })
    }

    /// Блокирует/разблокирует API ключ (удаляем запись из api_keys)
    pub async fn toggle_api_key(
        &self,
        key_id: &str,
        is_active: bool,
    ) -> Result<(), Box<dyn std::error::Error>> {
        // Удаляем или добавляем запись - простая блокировка через удаление
        if !is_active {
            sqlx::query(
                "DELETE FROM api_keys WHERE key_hash = $1"
            )
            .bind(key_id)
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    /// Удаляет API ключ
    pub async fn delete_api_key(&self, key_id: &str) -> Result<(), Box<dyn std::error::Error>> {
        // Удаляем из api_keys (по key_hash)
        sqlx::query("DELETE FROM api_keys WHERE key_hash = $1")
            .bind(key_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }
}
