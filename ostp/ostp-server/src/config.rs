use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ServerConfig {
    pub bind_addr: String,
    pub stream_id: u16,
    pub max_padding: usize,
    pub access_keys_file: String,
    pub max_datagram_size: usize,
    pub peer_idle_timeout_secs: u64,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind_addr: "0.0.0.0:8443".to_string(),
            stream_id: 1,
            max_padding: 256,
            access_keys_file: "ostp-server-keys.txt".to_string(),
            max_datagram_size: 2048,
            peer_idle_timeout_secs: 120,
        }
    }
}

impl ServerConfig {
    pub fn config_path_near_binary() -> Result<PathBuf> {
        let exe = env::current_exe().context("failed to resolve current executable path")?;
        let dir = exe
            .parent()
            .context("failed to resolve executable directory")?;
        Ok(dir.join("ostp-server.toml"))
    }

    pub fn load_or_create_near_binary() -> Result<Self> {
        let path = Self::config_path_near_binary()?;

        if !path.exists() {
            let default_cfg = Self::default();
            let content = toml::to_string_pretty(&default_cfg)
                .context("failed to serialize default server config")?;
            fs::write(&path, content).with_context(|| {
                format!(
                    "failed to create default server config near binary at {}",
                    path.display()
                )
            })?;
        }

        let raw = fs::read_to_string(&path)
            .with_context(|| format!("failed to read config file {}", path.display()))?;
        toml::from_str::<ServerConfig>(&raw)
            .with_context(|| format!("failed to parse config file {}", path.display()))
    }

    pub fn access_keys_path_near_binary(&self) -> Result<PathBuf> {
        let cfg_path = Self::config_path_near_binary()?;
        let dir = cfg_path
            .parent()
            .context("failed to resolve server config directory")?;
        Ok(dir.join(&self.access_keys_file))
    }
}
