mod api;
mod auth;
mod billing;
mod config;
mod error;
mod node_manager;
mod proxy_gateway;
mod state;

use std::sync::Arc;
use colored::Colorize;
use config::Config;
use node_manager::ws_tunnel::TunnelState;
use node_manager::registry::RedisNodeRegistry;
use billing::engine::DefaultBillingEngine;
use billing::BillingEngine;
use api::routes::build_router;
use state::AppState;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

fn print_banner() {
    let banner = r#"
 ____        _        _                         
| __ ) _   _| |_ ___ / \__      ____ _ _   _   
|  _ \| | | | __/ _ / _ \ \ /\ / / _` | | | |  
| |_) | |_| | ||  __/ ___ \ V  V / (_| | |_| |  
|____/ \__, |\__\___/_/   \_\_/\_/ \__,_|\__, |  
       |___/                             |___/   
    "#;
    println!("{}", banner.cyan().bold());
    println!("{}", "═══════════════════════════════════════════════".dimmed());
    println!("  {} {}", "Service:".dimmed(), "Residential Proxy Master Node".white().bold());
    println!("  {} {}", "Version:".dimmed(), env!("CARGO_PKG_VERSION").yellow());
    println!("{}", "═══════════════════════════════════════════════".dimmed());
    println!();
}

fn status(icon: &str, label: &str, value: &str) {
    println!("  {} {} {}", icon, format!("{:<12}", label).dimmed(), value.green().bold());
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_target(false)
        .init();

    print_banner();

    // 1. Конфигурация
    let config = Config::from_env()?;
    status("✔", "Config", "loaded from .env");

    // 2. PostgreSQL
    let db_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(20)
        .connect(&config.database_url)
        .await?;
    status("✔", "Postgres", &config.database_url);

    // 3. Redis
    let redis_client = redis::Client::open(config.redis_url.as_str())
        .map_err(|e| anyhow::anyhow!(e))?;
    // Проверяем подключение
    let _conn = redis_client.get_multiplexed_async_connection().await
        .map_err(|e| anyhow::anyhow!("Redis connection failed: {}", e))?;
    status("✔", "Redis", &config.redis_url);

    // 4. Инициализация модулей
    let registry = Arc::new(RedisNodeRegistry::new(&config.redis_url)?);
    let authenticator = auth::Authenticator::new(db_pool.clone(), redis_client.clone());

    let app_state = Arc::new(AppState {
        db_pool: db_pool.clone(),
        redis_client: redis_client.clone(),
        registry: registry.clone(),
        authenticator,
        price_per_gb_usd: config.price_per_gb_usd,
    });

    let tunnel_state = Arc::new(TunnelState {
        registry: registry.clone(),
    });

    status("✔", "Auth", "authenticator ready");
    status("✔", "Billing", format!("${}/GB", config.price_per_gb_usd).as_str());

    // 5. REST API + WebSocket сервер
    let api_addr = format!("0.0.0.0:{}", config.api_port);
    let axum_listener = TcpListener::bind(&api_addr).await?;
    status("▶", "REST API", &format!("http://{}", api_addr));
    status("▶", "WebSocket", &format!("ws://{}/ws", api_addr));

    let router = build_router(app_state.clone(), tunnel_state);
    let axum_handle = tokio::spawn(async move {
        axum::serve(axum_listener, router).await.unwrap();
    });

    // 6. SOCKS5 TCP сервер
    let socks5_addr: std::net::SocketAddr = format!("0.0.0.0:{}", config.socks5_port).parse()?;
    status("▶", "SOCKS5", &format!("socks5://{}", socks5_addr));

    let socks_state = app_state.clone();
    let socks_handle = tokio::spawn(async move {
        proxy_gateway::server::run_socks5_server(socks5_addr, socks_state).await;
    });

    // 7. Фоновый воркер биллинга (flush Redis → Postgres каждые 60с)
    let billing_state = app_state.clone();
    let billing_handle = tokio::spawn(async move {
        let engine = DefaultBillingEngine {
            db_pool: billing_state.db_pool.clone(),
            redis_client: billing_state.redis_client.clone(),
            price_per_gb_usd: billing_state.price_per_gb_usd,
        };
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
        loop {
            interval.tick().await;
            if let Err(e) = engine.process_redis_flush().await {
                tracing::error!("Billing flush error: {}", e);
            }
        }
    });

    println!();
    println!("{}", "═══════════════════════════════════════════════".dimmed());
    println!("  {} {}", "Status:".dimmed(), "ALL SYSTEMS ONLINE".green().bold());
    println!("  {} {}", "Hint:".dimmed(), "Press Ctrl+C to shut down".yellow());
    println!("{}", "═══════════════════════════════════════════════".dimmed());
    println!();

    // 8. Graceful shutdown
    tokio::signal::ctrl_c().await?;
    println!("\n  {} {}", "⏻".yellow(), "Shutting down...".yellow().bold());

    axum_handle.abort();
    socks_handle.abort();
    billing_handle.abort();
    db_pool.close().await;

    println!("  {} {}", "✔".green(), "Master node stopped.".green().bold());
    Ok(())
}
