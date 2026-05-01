use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ClientConfig {
    pub ostp: OstpConfig,
    pub local_proxy: LocalProxyConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct OstpConfig {
    pub server_addr: String,
    pub local_bind_addr: String,
    #[serde(alias = "auth_token")]
    pub access_key: String,
    pub handshake_timeout_ms: u64,
    pub io_timeout_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct LocalProxyConfig {
    pub bind_addr: String,
    pub connect_timeout_ms: u64,
}

impl Default for OstpConfig {
    fn default() -> Self {
        Self {
            server_addr: "127.0.0.1:8443".to_string(),
            local_bind_addr: "0.0.0.0:0".to_string(),
            access_key: "replace-with-server-key".to_string(),
            handshake_timeout_ms: 10000,
            io_timeout_ms: 2500,
        }
    }
}

impl Default for LocalProxyConfig {
    fn default() -> Self {
        Self {
            bind_addr: "127.0.0.1:1088".to_string(),
            connect_timeout_ms: 15000,
        }
    }
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            ostp: OstpConfig::default(),
            local_proxy: LocalProxyConfig::default(),
        }
    }
}

impl ClientConfig {
    pub fn config_path_near_binary() -> Result<PathBuf> {
        let exe = env::current_exe().context("failed to resolve current executable path")?;
        let dir = exe
            .parent()
            .context("failed to resolve executable directory")?;
        Ok(dir.join("ostp-client.toml"))
    }

    pub fn load_or_create_near_binary() -> Result<Self> {
        let path = Self::config_path_near_binary()?;

        if !path.exists() {
            let default_cfg = Self::default();
            default_cfg.write_to_path(&path)?;
        }

        let raw = fs::read_to_string(&path)
            .with_context(|| format!("failed to read config file {}", path.display()))?;
        toml::from_str::<ClientConfig>(&raw)
            .with_context(|| format!("failed to parse config file {}", path.display()))
    }

    pub fn save_near_binary(&self) -> Result<()> {
        let path = Self::config_path_near_binary()?;
        self.write_to_path(&path)
    }

    fn write_to_path(&self, path: &PathBuf) -> Result<()> {
        let content = toml::to_string_pretty(self)
            .context("failed to serialize client config")?;
        fs::write(path, content)
            .with_context(|| format!("failed to write config file {}", path.display()))
    }
}
