use axum::{Router, routing::{get, post}, middleware};
use crate::auth::middleware::require_auth;
use crate::node_manager::ws_tunnel::{ws_upgrade_handler, TunnelState};
use crate::state::AppState;
use super::handlers;
use std::sync::Arc;

pub fn build_router(state: Arc<AppState>, tunnel_state: Arc<TunnelState>) -> Router {
    // Защищённые B2B эндпоинты
    let api_routes = Router::new()
        .route("/balance", get(handlers::get_balance))
        .route("/proxies", get(handlers::get_proxies))
        .layer(middleware::from_fn_with_state(state.clone(), require_auth))
        .with_state(state);

    Router::new()
        .nest("/api/v1", api_routes)
        .route("/ws", get(ws_upgrade_handler).with_state(tunnel_state))
        .with_state(())
}
