use axum::{
    http::{HeaderName, HeaderValue},
    middleware,
    routing::{get, post},
    Router,
};
use std::sync::Arc;
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::set_header::SetResponseHeaderLayer;
use tower_http::services::ServeDir;

use crate::auth::middleware::require_auth;
use crate::node_manager::ws_tunnel::{ws_upgrade_handler, TunnelState};
use crate::state::AppState;
use super::{app_update, business, business_auth, handlers, monitoring, public, vpn};

pub fn build_router(state: Arc<AppState>, tunnel_state: Arc<TunnelState>) -> Router {
    // Публичные эндпоинты мониторинга
    let monitoring_routes = Router::new()
        .route("/health", get(monitoring::health_handler))
        .route("/stats", get(monitoring::stats_handler))
        .with_state(state.clone());

    // Публичные эндпоинты аутентификации
    let auth_routes = Router::new()
        .route("/register-node", post(handlers::register_node))
        .route("/business/register", post(business_auth::register_business))
        .route("/business/login", post(business_auth::login_business))
        .route("/register-business", post(business_auth::register_business))
        .route("/login-business", post(business_auth::login_business))
        .route("/business/me", get(business_auth::get_business_session_me))
        .route("/business/tokens", post(business_auth::create_business_api_token))
        .route("/business/tokens", get(business_auth::list_business_api_tokens))
        .route("/business/tokens/:credential_id", axum::routing::delete(business_auth::revoke_business_api_token))
        .with_state(state.clone());

    // VPN gateway traffic reporting (internal, no auth required for gateways)
    let vpn_routes = Router::new()
        .route("/vpn/traffic-report", post(vpn::report_vpn_traffic))
        .route("/vpn/check-client", get(vpn::check_client_session))
        .with_state(state.clone());

    let public_routes = Router::new()
        .route("/downloads/ticket", post(public::create_download_ticket))
        .route("/downloads/byteaway-release.apk", get(public::download_apk_with_ticket))
        .with_state(state.clone());

    // Защищённые B2B/B2C эндпоинты
    let api_routes = Router::new()
        .route("/balance", get(handlers::get_balance))
        .route("/proxies", get(handlers::get_proxies))
        .route("/stats", get(handlers::get_stats))
        .route("/vpn/config", get(handlers::get_vpn_config))
        .route("/app/update/manifest", get(app_update::get_secure_manifest))
        .route("/app/update/apk", get(app_update::download_secure_apk))
        // B2B proxy credentials management
        .route("/business/proxy-credentials", post(business::create_proxy_credentials))
        .route("/business/proxy-credentials", get(business::list_proxy_credentials))
        .layer(middleware::from_fn_with_state(state.clone(), require_auth))
        .with_state(state.clone());

    Router::new()
        .nest("/api/v1/auth", auth_routes)
        .route("/api/v1/business/register", post(business_auth::register_business).with_state(state.clone()))
        .route("/api/v1/business/login", post(business_auth::login_business).with_state(state.clone()))
        .nest("/api/v1/public", public_routes)
        .nest("/api/v1/monitoring", monitoring_routes)
        .nest("/api/v1", api_routes)
        .nest("/api/v1", vpn_routes)
        .route("/ws", get(ws_upgrade_handler).with_state(tunnel_state))
        .nest_service("/admin", ServeDir::new("admin"))
        .layer(SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static("strict-transport-security"),
            HeaderValue::from_static("max-age=31536000; includeSubDomains"),
        ))
        .layer(SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static("cross-origin-opener-policy"),
            HeaderValue::from_static("same-origin"),
        ))
        .layer(SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static("permissions-policy"),
            HeaderValue::from_static("camera=(), microphone=(), geolocation=()"),
        ))
        .layer(SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static("referrer-policy"),
            HeaderValue::from_static("no-referrer"),
        ))
        .layer(SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static("x-frame-options"),
            HeaderValue::from_static("DENY"),
        ))
        .layer(SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static("x-content-type-options"),
            HeaderValue::from_static("nosniff"),
        ))
        .layer(RequestBodyLimitLayer::new(1024 * 1024))
        .with_state(())
}
