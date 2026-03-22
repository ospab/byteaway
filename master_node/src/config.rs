use anyhow::Result;
use dotenvy::dotenv;
use std::env;

pub struct Config {
    pub database_url: String,
    pub redis_url: String,
    pub api_port: u16,
    pub socks5_port: u16,
    pub price_per_gb_usd: f64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        dotenv().ok();
        Ok(Self {
            database_url: env::var("DATABASE_URL").expect("DATABASE_URL must be set"),
            redis_url: env::var("REDIS_URL").expect("REDIS_URL must be set"),
            api_port: env::var("API_PORT").unwrap_or_else(|_| "3000".to_string()).parse()?,
            socks5_port: env::var("SOCKS5_PORT").unwrap_or_else(|_| "1080".to_string()).parse()?,
            price_per_gb_usd: env::var("PRICE_PER_GB_USD").unwrap_or_else(|_| "5.0".to_string()).parse()?,
        })
    }
}
