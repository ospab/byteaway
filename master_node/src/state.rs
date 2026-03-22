use std::sync::Arc;
use crate::auth::Authenticator;
use crate::node_manager::registry::RedisNodeRegistry;

/// Глобальное состояние приложения, доступное всем хендлерам через Arc
pub struct AppState {
    pub db_pool: sqlx::PgPool,
    pub redis_client: redis::Client,
    pub registry: Arc<RedisNodeRegistry>,
    pub authenticator: Authenticator,
    pub price_per_gb_usd: f64,
}
