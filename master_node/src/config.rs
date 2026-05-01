use anyhow::Result;
use dotenvy::dotenv;
use std::env;

#[allow(dead_code)]
#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub redis_url: String,
    pub api_port: u16,
    pub socks5_port: u16,
    pub price_per_gb_usd: f64,
    pub auto_add_balance_usd: f64,
    // Performance settings
    pub max_db_connections: u32,
    pub request_timeout_secs: u64,
    pub connection_pool_idle_timeout: u64,
    pub enable_request_compression: bool,
    pub max_concurrent_requests: usize,
    // Debug mode - verbose logging
    pub debug_mode: bool,
    // VPN / Reality
    pub vpn_public_host: String,
    pub vpn_port: u16,
    #[allow(dead_code)]
    pub reality_private_key: String,
    pub reality_public_key: String,
    pub reality_short_id: String,
    pub reality_dest: String,
    pub vpn_client_uuid: String,
    pub node_quic_enabled: bool,
    pub node_quic_port: u16,
    pub node_quic_cert_path: String,
    pub node_quic_key_path: String,
    #[allow(dead_code)]
    pub node_ostp_enabled: bool,
    #[allow(dead_code)]
    pub node_ostp_port: u16,
    // Security settings
    pub rate_limit_requests_per_minute: u32,
    pub max_request_size_mb: usize,
    pub enable_cors: bool,
    pub trusted_origins: Vec<String>,
    // Monitoring
    pub enable_metrics: bool,
    pub metrics_port: u16,
    pub health_check_interval_secs: u64,
    // Billing optimization
    pub billing_flush_interval_secs: u64,
    pub billing_batch_size: usize,
    pub turnstile_secret_key: String,
    pub turnstile_verify_url: String,
    pub app_update_manifest_path: String,
    pub public_base_url: String,
    // Free tier settings
    pub free_daily_limit_bytes: u64,
    pub traffic_reward_bytes: u64,
    pub traffic_reward_days: f64,
    // Admin key for monitoring API
    pub admin_api_key: String,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        dotenv().ok();
        Ok(Self {
            database_url: env::var("DATABASE_URL").expect("DATABASE_URL must be set"),
            redis_url: env::var("REDIS_URL").expect("REDIS_URL must be set"),
            api_port: env::var("API_PORT").unwrap_or_else(|_| "3000".to_string()).parse()?,
            socks5_port: env::var("SOCKS5_PORT").unwrap_or_else(|_| "31280".to_string()).parse()?,
            price_per_gb_usd: env::var("PRICE_PER_GB_USD").unwrap_or_else(|_| "5.0".to_string()).parse()?,
            auto_add_balance_usd: env::var("AUTO_ADD_BALANCE_USD").unwrap_or_else(|_| "0".to_string()).parse()?,
            // Performance settings with sensible defaults
            max_db_connections: env::var("MAX_DB_CONNECTIONS")
                .unwrap_or_else(|_| "50".to_string())
                .parse()?,
            request_timeout_secs: env::var("REQUEST_TIMEOUT_SECS")
                .unwrap_or_else(|_| "30".to_string())
                .parse()?,
            connection_pool_idle_timeout: env::var("CONNECTION_POOL_IDLE_TIMEOUT_SECS")
                .unwrap_or_else(|_| "300".to_string())
                .parse()?,
            enable_request_compression: env::var("ENABLE_REQUEST_COMPRESSION")
                .unwrap_or_else(|_| "true".to_string())
                .parse::<bool>()
                .unwrap_or(true),
            max_concurrent_requests: env::var("MAX_CONCURRENT_REQUESTS")
                .unwrap_or_else(|_| "1000".to_string())
                .parse()?,
            debug_mode: env::var("DEBUG")
                .unwrap_or_else(|_| "false".to_string())
                .parse::<bool>()
                .unwrap_or(false),
            vpn_public_host: env::var("VPN_PUBLIC_HOST").expect("VPN_PUBLIC_HOST must be set"),
            vpn_port: env::var("VPN_PORT").unwrap_or_else(|_| "5443".to_string()).parse()?,
            reality_private_key: env::var("REALITY_PRIVATE_KEY").expect("REALITY_PRIVATE_KEY must be set"),
            reality_public_key: env::var("REALITY_PUBLIC_KEY").expect("REALITY_PUBLIC_KEY must be set"),
            reality_short_id: env::var("REALITY_SHORT_ID").unwrap_or_else(|_| "0123456789abcdef".to_string()),
            reality_dest: env::var("REALITY_DEST").unwrap_or_else(|_| "google.com:443".to_string()),
            vpn_client_uuid: env::var("VPN_CLIENT_UUID")
                .unwrap_or_else(|_| "49557a2f-e8b8-4c63-9524-76839a8579ca".to_string()),
            node_quic_enabled: env::var("NODE_QUIC_ENABLED")
                .unwrap_or_else(|_| "true".to_string())
                .parse::<bool>()
                .unwrap_or(true),
            node_quic_port: env::var("NODE_QUIC_PORT")
                .unwrap_or_else(|_| "3443".to_string())
                .parse()?,
            node_quic_cert_path: env::var("NODE_QUIC_CERT_PATH")
                .unwrap_or_else(|_| "./certs/node_quic.crt".to_string()),
            node_quic_key_path: env::var("NODE_QUIC_KEY_PATH")
                .unwrap_or_else(|_| "./certs/node_quic.key".to_string()),
            node_ostp_enabled: env::var("NODE_OSTP_ENABLED")
                .unwrap_or_else(|_| "true".to_string())
                .parse::<bool>()
                .unwrap_or(true),
            node_ostp_port: env::var("NODE_OSTP_PORT")
                .unwrap_or_else(|_| "8443".to_string())
                .parse()?,
            // Security settings
            rate_limit_requests_per_minute: env::var("RATE_LIMIT_REQUESTS_PER_MINUTE")
                .unwrap_or_else(|_| "60".to_string())
                .parse()?,
            max_request_size_mb: env::var("MAX_REQUEST_SIZE_MB")
                .unwrap_or_else(|_| "10".to_string())
                .parse()?,
            enable_cors: env::var("ENABLE_CORS")
                .unwrap_or_else(|_| "true".to_string())
                .parse::<bool>()
                .unwrap_or(true),
            trusted_origins: env::var("TRUSTED_ORIGINS")
                .unwrap_or_else(|_| "http://localhost:3000,https://byteaway.xyz".to_string())
                .split(',')
                .map(|s| s.trim().to_string())
                .collect(),
            // Monitoring
            enable_metrics: env::var("ENABLE_METRICS")
                .unwrap_or_else(|_| "true".to_string())
                .parse::<bool>()
                .unwrap_or(true),
            metrics_port: env::var("METRICS_PORT")
                .unwrap_or_else(|_| "9090".to_string())
                .parse()?,
            health_check_interval_secs: env::var("HEALTH_CHECK_INTERVAL_SECS")
                .unwrap_or_else(|_| "30".to_string())
                .parse()?,
            // Billing optimization
            billing_flush_interval_secs: env::var("BILLING_FLUSH_INTERVAL_SECS")
                .unwrap_or_else(|_| "60".to_string())
                .parse()?,
            billing_batch_size: env::var("BILLING_BATCH_SIZE")
                .unwrap_or_else(|_| "100".to_string())
                .parse()?,
            turnstile_secret_key: env::var("TURNSTILE_SECRET_KEY")
                .expect("TURNSTILE_SECRET_KEY must be set"),
            turnstile_verify_url: env::var("TURNSTILE_VERIFY_URL")
                .unwrap_or_else(|_| "https://challenges.cloudflare.com/turnstile/v0/siteverify".to_string()),
            app_update_manifest_path: env::var("APP_UPDATE_MANIFEST_PATH")
                .unwrap_or_else(|_| "/var/www/byteaway-web/dist/downloads/android.json".to_string()),
            public_base_url: env::var("PUBLIC_BASE_URL")
                .unwrap_or_else(|_| "https://byteaway.xyz".to_string()),
            // Free tier settings: 1GB daily limit, 200MB = 1 day reward
            free_daily_limit_bytes: env::var("FREE_DAILY_LIMIT_BYTES")
                .unwrap_or_else(|_| "1073741824".to_string())
                .parse()?,
            traffic_reward_bytes: env::var("TRAFFIC_REWARD_BYTES")
                .unwrap_or_else(|_| "209715200".to_string())
                .parse()?,
            traffic_reward_days: env::var("TRAFFIC_REWARD_DAYS")
                .unwrap_or_else(|_| "1.0".to_string())
                .parse()?,
            admin_api_key: env::var("ADMIN_API_KEY")
                .unwrap_or_else(|_| "change-me-in-production".to_string()),
        })
    }
}
