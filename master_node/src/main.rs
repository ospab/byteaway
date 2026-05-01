mod api;
mod auth;
mod billing;
mod config;
mod error;
mod node_manager;
mod proxy_gateway;
mod state;
mod vpn;
mod singbox_server;

use std::sync::Arc;
use colored::Colorize;
use config::Config;
use node_manager::quic_tunnel::{run_quic_server, QuicTunnelState};
use node_manager::ws_tunnel::TunnelState;
use node_manager::registry::RedisNodeRegistry;
use billing::engine::DefaultBillingEngine;
use billing::BillingEngine;
use api::routes::build_router;
use state::AppState;
use crate::vpn::gateway::{VpnGatewayRegistry, VpnGateway};
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

fn print_banner() {}

fn status(_icon: &str, _label: &str, _value: &str) {}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Install default crypto provider for rustls 0.23+
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("Failed to install default crypto provider");

    dotenvy::dotenv().ok();

    // Load config first to check debug mode
    let config = Config::from_env()?;
    
    // Configure logging based on debug mode
    let log_level = if config.debug_mode {
        "debug,sqlx=warn"
    } else {
        "info,sqlx=warn,master_node=info"
    };
    
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(log_level)))
        .with_target(config.debug_mode)
        .init();

    print_banner();

    // 1. Конфигурация уже загружена выше для логирования
    status("✔", "Config", "loaded from .env");

    // 2. PostgreSQL
    let db_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(20)
        .connect(&config.database_url)
        .await?;
    status("✔", "Postgres", &config.database_url);

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&db_pool)
        .await?;

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
    let billing_engine = Arc::new(DefaultBillingEngine {
        db_pool: db_pool.clone(),
        redis_client: redis_client.clone(),
        price_per_gb_usd: config.price_per_gb_usd,
    });

    // 4a. VPN Gateway registry
    let default_gateway = VpnGateway {
        id: "default".to_string(),
        public_host: config.vpn_public_host.clone(),
        public_port: config.vpn_port,
        region: Some("default".to_string()),
        max_clients: 1000,
        current_clients: 0,
        is_healthy: true,
        reality_public_key: config.reality_public_key.clone(),
        reality_short_id: config.reality_short_id.clone(),
    };
    let vpn_registry = Arc::new(VpnGatewayRegistry::new(
        &config.redis_url,
        db_pool.clone(),
        default_gateway,
    )?);

    let app_state = Arc::new(AppState {
        db_pool: db_pool.clone(),
        redis_client: redis_client.clone(),
        registry: registry.clone(),
        vpn_registry: vpn_registry.clone(),
        authenticator,
        billing_engine: billing_engine.clone(),
        price_per_gb_usd: config.price_per_gb_usd,
        auto_add_balance_usd: config.auto_add_balance_usd,
        socks5_port: config.socks5_port,
        vpn_public_host: config.vpn_public_host,
        vpn_port: config.vpn_port,
        reality_dest: config.reality_dest.clone(),
        reality_private_key: config.reality_private_key,
        reality_public_key: config.reality_public_key,
        reality_short_id: config.reality_short_id,
        vpn_client_uuid: config.vpn_client_uuid,
        failed_node_selections: std::sync::atomic::AtomicU32::new(0),
        turnstile_secret_key: config.turnstile_secret_key,
        turnstile_verify_url: config.turnstile_verify_url,
        app_update_manifest_path: config.app_update_manifest_path,
        public_base_url: config.public_base_url,
        admin_api_key: config.admin_api_key,
    });



    let tunnel_state = Arc::new(TunnelState {
        registry: registry.clone(),
        _app_state: app_state.clone(),
    });

    let quic_tunnel_state = Arc::new(QuicTunnelState {
        registry: registry.clone(),
        app_state: app_state.clone(),
    });

    // Start sing-box server
    let singbox_config_json = singbox_server::generate_singbox_config(
        &app_state.vpn_public_host,
        app_state.vpn_port,
        &app_state.reality_private_key,
        &app_state.reality_public_key,
        &app_state.reality_short_id,
        &app_state.reality_dest,
        &app_state.vpn_client_uuid,
        4433, // Default HY2 port
        "byteaway_hy2_secret", // Default HY2 password
        &config.node_quic_cert_path,
        &config.node_quic_key_path,
    )?;

    let singbox_config_path = "./singbox_config.json";
    std::fs::write(singbox_config_path, &singbox_config_json)?;

    // Print all listening ports first
    println!("Master node listening ports:");
    println!("  - REST API & WebSocket: {}", config.api_port);
    println!("  - SOCKS5 Proxy: {}", config.socks5_port);
    if config.node_quic_enabled {
        println!("  - Node QUIC: {}", config.node_quic_port);
    }
    println!("  - Node WS fallback: 5443");

    let mut singbox_server = singbox_server::SingBoxServer::new(singbox_config_path.to_string());
    if let Err(e) = singbox_server.start().await {
        tracing::error!("Failed to start sing-box: {:?}", e);
    }


    status("✔", "Auth", "authenticator ready");
    status("✔", "VPN Gateways", "registry ready");
    status("✔", "Billing", format!("${}/GB", config.price_per_gb_usd).as_str());

    // 5. REST API + WebSocket сервер
    let api_addr = format!("0.0.0.0:{}", config.api_port);
    let axum_listener = TcpListener::bind(&api_addr).await
        .map_err(|e| anyhow::anyhow!("CRITICAL: API port {} is already in use! ({})", config.api_port, e))?;
    
    status("▶", "REST API", &format!("http://{}", api_addr));
    status("▶", "WebSocket", &format!("ws://{}/ws", api_addr));

    let router = build_router(app_state.clone(), tunnel_state);
    let axum_handle = tokio::spawn(async move {
        axum::serve(
            axum_listener,
            router.into_make_service_with_connect_info::<std::net::SocketAddr>(),
        )
        .await
        .unwrap();
    });

    // 6. SOCKS5 TCP сервер
    let socks5_addr: std::net::SocketAddr = format!("0.0.0.0:{}", config.socks5_port).parse()?;
    let socks5_listener = TcpListener::bind(socks5_addr).await
        .map_err(|e| anyhow::anyhow!("CRITICAL: SOCKS5 port {} is already in use! ({})", config.socks5_port, e))?;

    status("▶", "SOCKS5", &format!("socks5://{}", socks5_addr));

    let socks_state = app_state.clone();
    let socks_handle = tokio::spawn(async move {
        proxy_gateway::server::run_socks5_server(socks5_listener, socks_state).await;
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

    // 7a. QUIC node ingress (optional)
    let quic_handle = if config.node_quic_enabled {
        let quic_addr: std::net::SocketAddr = format!("0.0.0.0:{}", config.node_quic_port).parse()?;
        status("▶", "Node QUIC", &format!("quic://{}", quic_addr));
        let cert_path = config.node_quic_cert_path.clone();
        let key_path = config.node_quic_key_path.clone();
        let state = quic_tunnel_state.clone();
        Some(tokio::spawn(async move {
            if let Err(e) = run_quic_server(quic_addr, &cert_path, &key_path, state, "QUIC").await {
                tracing::error!("QUIC node ingress crashed: {e}");
            }
        }))
    } else {
        status("•", "Node QUIC", "disabled");
        None
    };

    // 7b. WS fallback node ingress (TCP-based)
    let _ws_fallback_handle = if config.node_quic_enabled {
        let ws_addr: std::net::SocketAddr = "0.0.0.0:5443".parse()?;
        status("▶", "Node WS", &format!("ws://{}", ws_addr));
        Some(tokio::spawn(async move {
            // WS tunnel handled by axum /ws route
            tokio::signal::ctrl_c().await.ok();
        }))
    } else {
        None
    };





    // 8. Graceful shutdown
    tokio::signal::ctrl_c().await?;
    println!("\n  {} {}", "⏻".yellow(), "Shutting down...".yellow().bold());

    axum_handle.abort();
    socks_handle.abort();
    billing_handle.abort();
    if let Some(h) = quic_handle {
        h.abort();
    }
    singbox_server.stop().await;
    db_pool.close().await;

    println!("  {} {}", "✔".green(), "Master node stopped.".green().bold());
    Ok(())
}
