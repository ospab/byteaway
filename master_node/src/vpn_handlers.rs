use axum::{
    extract::{Query, State},
    response::Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    auth::AuthContext,
    error::AppError,
    state::AppState,
};

#[derive(Debug, Serialize)]
pub struct VpnConfigResponse {
    pub xray_config_json: serde_json::Value,
    pub assigned_ip: String,
    pub tier: String,
    pub max_speed_mbps: u32,
    pub vless_link: String,
}

#[derive(Debug, Deserialize)]
pub struct VpnConfigQuery {
    #[serde(default)]
    use_ru_egress: bool,
}

/// Generates a complete Xray configuration for a client to establish a VPN connection.
pub async fn get_vpn_config(
    State(state): State<Arc<AppState>>,
    auth_ctx: AuthContext,
    Query(query): Query<VpnConfigQuery>,
) -> Result<Json<VpnConfigResponse>, AppError> {
    let client_id = auth_ctx.client_id;
    let vpn_client_uuid = Uuid::new_v5(&Uuid::NAMESPACE_DNS, client_id.to_string().as_bytes());

    // Define server details based on whether a Russian egress is requested
    let (vpn_public_host, reality_host) = if query.use_ru_egress {
        (&state.config.ru_vpn_public_host, &state.config.ru_reality_host)
    } else {
        (&state.config.vpn_public_host, &state.config.reality_host)
    };

    // Construct the VLESS link for sharing/manual configuration
    let vless_link = format!(
        "vless://{}@{}:{}?encryption=none&security=reality&sni={}&fp=chrome&pbk={}&sid={}",
        vpn_client_uuid,
        vpn_public_host,
        state.config.vpn_port,
        reality_host,
        state.config.reality_public_key,
        state.config.reality_short_id
    );

    // Build the full Xray JSON configuration
    let xray_config = serde_json::json!({
        "log": { "loglevel": "warning" },
        "dns": {
            "servers": ["1.1.1.1", "8.8.8.8", "localhost"]
        },
        "routing": {
            "domainStrategy": "AsIs",
            "rules": []
        },
        "inbounds": [
            {
                "port": 10808,
                "listen": "127.0.0.1",
                "protocol": "socks",
                "settings": { "auth": "noauth", "udp": true }
            }
        ],
        "outbounds": [
            {
                "protocol": "vless",
                "settings": {
                    "vnext": [{
                        "address": vpn_public_host,
                        "port": state.config.vpn_port,
                        "users": [{
                            "id": vpn_client_uuid.to_string(),
                            "encryption": "none",
                            "flow": "xtls-rprx-vision"
                        }]
                    }]
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": {
                        "show": false,
                        "dest": reality_host,
                        "xver": 0,
                        "serverNames": [reality_host],
                        "privateKey": &state.config.reality_private_key,
                        "minClientVer": "",
                        "maxClientVer": "",
                        "maxTimeDiff": 0,
                        "shortId": &state.config.reality_short_id,
                    }
                }
            },
            { "protocol": "freedom", "tag": "direct" },
            { "protocol": "blackhole", "tag": "block" }
        ]
    });

    let response = VpnConfigResponse {
        xray_config_json: xray_config,
        assigned_ip: "10.8.0.1".to_string(), // Placeholder, IP management would be more complex
        tier: auth_ctx.tier.to_string(),
        max_speed_mbps: 0, // Placeholder
        vless_link,
    };

    Ok(Json(response))
}
