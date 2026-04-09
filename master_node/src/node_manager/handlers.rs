use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
};
use serde::Deserialize;
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    api::monitoring::{NodeRegistrationRequest, NodeRegistrationResponse},
    auth::AuthContext,
    error::AppError,
    state::AppState,
};

#[derive(Deserialize)]
pub struct RegisterNodeQuery {
    pub token: String,
}

pub async fn register_node_handler(
    State(state): State<Arc<AppState>>,
    Query(query): Query<RegisterNodeQuery>,
    Json(req): Json<NodeRegistrationRequest>,
) -> Result<Json<NodeRegistrationResponse>, AppError> {
    // Authenticate the request using the provided token
    let auth_ctx: AuthContext = state.authenticator.authenticate(&query.token, Some(&req.device_id))?;

    // Generate a new JWT for the node's session
    let token = match state.authenticator.generate_jwt(
        auth_ctx.client_id,
        auth_ctx.device_id.clone(),
        auth_ctx.subscription_level,
        auth_ctx.tier,
    ) {
        Ok(token) => token,
        Err(_) => return Err(AppError::new(StatusCode::INTERNAL_SERVER_ERROR, "Failed to generate token")),
    };

    // Determine MTU and bootstrap proxy config based on the requested transport
    let (mtu, xray_config_json) = match req.transport.as_str() {
        "quic" => {
            // For QUIC, suggest a smaller, safer MTU to avoid fragmentation. No proxy config is needed.
            (Some(1280), None)
        }
        "ws" | "hy2" => {
            // For TCP-based transports like WebSocket, a larger MTU is generally safe.
            // Provide a bootstrap proxy config to help the node connect from behind restrictive firewalls.
            let proxy_config = serde_json::json!({
                "outbounds": [{
                    "protocol": "vless",
                    "settings": {
                        "vnext": [{
                            "address": &state.config.vpn_public_host,
                            "port": 443,
                            "users": [{ 
                                "id": Uuid::new_v4().to_string(),
                                "encryption": "none"
                            }]
                        }]
                    },
                    "streamSettings": {
                        "network": "ws",
                        "security": "tls",
                        "wsSettings": { "path": "/ws_proxy" } // A dedicated path for bootstrap connections
                    }
                }]
            });
            let config_str = serde_json::to_string(&proxy_config).unwrap_or_default();
            (Some(1420), Some(config_str))
        }
        _ => (None, None), // Default case for unknown transports
    };

    let response = NodeRegistrationResponse {
        token,
        xray_config_json,
        mtu,
    };

    Ok(Json(response))
}
