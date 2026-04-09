use anyhow::Result;
use dotenvy::dotenv;
use std::env;

pub struct Config {
    pub database_url: String,
    pub redis_url: String,
    pub api_port: u16,
    pub socks5_port: u16,
    pub price_per_gb_usd: f64,
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
    pub turnstile_secret_key: String,
    pub turnstile_verify_url: String,
    pub app_update_manifest_path: String,
    pub public_base_url: String,
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
            turnstile_secret_key: env::var("TURNSTILE_SECRET_KEY")
                .expect("TURNSTILE_SECRET_KEY must be set"),
            turnstile_verify_url: env::var("TURNSTILE_VERIFY_URL")
                .unwrap_or_else(|_| "https://challenges.cloudflare.com/turnstile/v0/siteverify".to_string()),
            app_update_manifest_path: env::var("APP_UPDATE_MANIFEST_PATH")
                .unwrap_or_else(|_| "/var/www/byteaway-web/dist/downloads/android.json".to_string()),
            public_base_url: env::var("PUBLIC_BASE_URL")
                .unwrap_or_else(|_| "https://byteaway.xyz".to_string()),
        })
    }
}
