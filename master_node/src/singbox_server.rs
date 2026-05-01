use anyhow::{anyhow, Result};
use serde_json::json;
use std::path::Path;
use tokio::process::{Child, Command};
use tracing::{info, error};

pub struct SingBoxServer {
    child: Option<Child>,
    config_path: String,
}

impl SingBoxServer {
    pub fn new(config_path: String) -> Self {
        Self {
            child: None,
            config_path,
        }
    }

    pub async fn start(&mut self) -> Result<()> {
        if self.child.is_some() {
            return Ok(());
        }

        // Check if sing-box binary exists
        let mut singbox_path = "./sing-box-1.13.11-linux-amd64/sing-box".to_string();
        if !Path::new(&singbox_path).exists() {
            singbox_path = "../sing-box-1.13.11-linux-amd64/sing-box".to_string();
        }
        if !Path::new(&singbox_path).exists() {
            singbox_path = "./sing-box".to_string();
        }
        if !Path::new(&singbox_path).exists() {
            return Err(anyhow!("sing-box binary not found"));
        }

        // Make binary executable
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&singbox_path)?.permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&singbox_path, perms)?;
            info!("Set executable permissions on {}", singbox_path);
        }

        // Check if config file exists
        if !Path::new(&self.config_path).exists() {
            return Err(anyhow!("sing-box config not found at {}", self.config_path));
        }

        info!("Starting sing-box server with config: {}", self.config_path);

        let child = Command::new("/bin/sh")
            .arg("-c")
            .arg(format!("{} run -c {}", singbox_path, self.config_path))
            .spawn()
            .map_err(|e| {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    let mode = std::fs::metadata(&singbox_path)
                        .map(|m| m.permissions().mode() & 0o777)
                        .unwrap_or(0);
                    anyhow!("Failed to spawn sing-box via shell: {}. Binary: {}, Config: {}, File mode: {:o}", e, singbox_path, self.config_path, mode)
                }
                #[cfg(not(unix))]
                anyhow!("Failed to spawn sing-box: {}. Binary: {}, Config: {}", e, singbox_path, self.config_path)
            })?;

        self.child = Some(child);
        info!("sing-box server started");
        Ok(())
    }

    pub async fn stop(&mut self) {
        if let Some(mut child) = self.child.take() {
            info!("Stopping sing-box server");
            if let Err(e) = child.kill().await {
                error!("Failed to kill sing-box: {}", e);
            }
        }
    }
}

pub fn generate_singbox_config(
    _public_host: &str,
    public_port: u16,
    reality_private_key: &str,
    _reality_public_key: &str,
    reality_short_id: &str,
    reality_dest: &str,
    client_uuid: &str,
    hy2_port: u16,
    hy2_password: &str,
    cert_path: &str,
    key_path: &str,
) -> Result<String> {
    let config = json!({
        "log": {
            "level": "info"
        },
        "dns": {
            "servers": [
                {
                    "type": "udp",
                    "tag": "dns-direct",
                    "server": "1.1.1.1",
                    "server_port": 53
                }
            ],
            "strategy": "ipv4_only"
        },
        "inbounds": [
            {
                "type": "vless",
                "tag": "vless-in",
                "listen": "::",
                "listen_port": public_port,
                "users": [
                    {
                        "uuid": client_uuid,
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "tls": {
                    "enabled": true,
                    "reality": {
                        "enabled": true,
                        "handshake": {
                            "server": reality_dest,
                            "server_port": 443
                        },
                        "private_key": reality_private_key,
                        "short_id": [
                            reality_short_id
                        ]
                    }
                }
            },
            {
                "type": "hysteria2",
                "tag": "hy2-in",
                "listen": "::",
                "listen_port": hy2_port,
                "users": [
                    {
                        "password": hy2_password
                    }
                ],
                "tls": {
                    "enabled": true,
                    "certificate_path": cert_path,
                    "key_path": key_path
                }
            }
        ],
        "outbounds": [
            {
                "type": "direct",
                "tag": "direct"
            }
        ],
        "route": {
            "rules": [
                {
                    "protocol": "dns",
                    "action": "hijack-dns"
                }
            ]
        }
    });

    Ok(serde_json::to_string_pretty(&config)?)
}
