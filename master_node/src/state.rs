use std::sync::Arc;
use crate::auth::Authenticator;
use crate::billing::BillingEngine;

use crate::node_manager::registry::RedisNodeRegistry;
use crate::vpn::gateway::VpnGatewayRegistry;

/// Глобальное состояние приложения, доступное всем хендлерам через Arc
pub struct AppState {
    pub db_pool: sqlx::PgPool,
    pub redis_client: redis::Client,
    pub registry: Arc<RedisNodeRegistry>,
    #[allow(dead_code)]
    pub vpn_registry: Arc<VpnGatewayRegistry>,
    pub authenticator: Authenticator,
    pub billing_engine: Arc<dyn BillingEngine>,
    pub price_per_gb_usd: f64,
    pub auto_add_balance_usd: f64,  // Автоматически добавлять баланс при создании токена
    pub socks5_port: u16,
    pub vpn_public_host: String,
    pub vpn_port: u16,
    #[allow(dead_code)]
    pub reality_dest: String,
    #[allow(dead_code)]
    pub reality_private_key: String,
    pub reality_public_key: String,
    pub reality_short_id: String,
    pub vpn_client_uuid: String,
    pub failed_node_selections: std::sync::atomic::AtomicU32,
    pub turnstile_secret_key: String,
    pub turnstile_verify_url: String,
    pub app_update_manifest_path: String,
    pub public_base_url: String,
    pub admin_api_key: String,
}
