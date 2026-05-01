use crate::node_manager::registry::NodeRegistry;
use axum::{extract::State, response::Json};
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub active_nodes: usize,
}



#[derive(Debug, Serialize, Deserialize)]
pub struct StatsResponse {
    pub active_nodes: usize,
    pub nodes_with_sessions: usize,
    pub max_sessions_on_single_node: usize,
    pub generated_at_unix: u64,
}


/// Эндпоинт для проверки здоровья сервера
pub async fn health_handler(
    State(state): State<Arc<AppState>>,
) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        active_nodes: NodeRegistry::active_connections(&*state.registry).len(),
    })
}

/// Эндпоинт для агрегированной статистики по активным нодам
pub async fn stats_handler(
    State(state): State<Arc<AppState>>,
) -> Json<StatsResponse> {
    let mut nodes_with_sessions = 0usize;
    let mut max_sessions_on_single_node = 0usize;

    for entry in NodeRegistry::active_connections(&*state.registry).iter() {
        let count: u32 = entry.value().active_sessions.load(std::sync::atomic::Ordering::Relaxed);
        let count_usize = count as usize;
        if count_usize > 0 {
            nodes_with_sessions += 1;
        }
        if count_usize > max_sessions_on_single_node {
            max_sessions_on_single_node = count_usize;
        }
    }

    Json(StatsResponse {
        active_nodes: NodeRegistry::active_connections(&*state.registry).len(),
        nodes_with_sessions,
        max_sessions_on_single_node,
        generated_at_unix: chrono::Utc::now().timestamp() as u64,
    })
}
