use axum::{extract::State, Json};
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::sync::atomic::Ordering;

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
        active_nodes: state.registry.active_connections.len(),
    })
}

/// Эндпоинт для агрегированной статистики по активным нодам
pub async fn stats_handler(
    State(state): State<Arc<AppState>>,
) -> Json<StatsResponse> {
    let mut nodes_with_sessions = 0usize;
    let mut max_sessions_on_single_node = 0usize;

    for entry in state.registry.active_connections.iter() {
        let count = entry.value().active_sessions.load(Ordering::Relaxed) as usize;
        if count > 0 {
            nodes_with_sessions += 1;
        }
        if count > max_sessions_on_single_node {
            max_sessions_on_single_node = count;
        }
    }

    Json(StatsResponse {
        active_nodes: state.registry.active_connections.len(),
        nodes_with_sessions,
        max_sessions_on_single_node,
        generated_at_unix: chrono::Utc::now().timestamp() as u64,
    })
}
