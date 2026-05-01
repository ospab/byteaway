use reqwest::Client;
use serde::{Deserialize, Serialize};
use anyhow::Result;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SystemStats {
    pub total_clients: i64,
    pub active_devices: i64,
    pub total_traffic_gb: String,
    pub total_balance_usd: String,
    pub active_sessions: i64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ClientInfo {
    pub id: uuid::Uuid,
    pub email: String,
    pub balance_usd: String,
    pub created_at: String,
    pub device_count: i64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DeviceInfo {
    pub id: uuid::Uuid,
    pub client_id: uuid::Uuid,
    pub hwid: String,
    pub vless_uuid: String,
    pub device_name: Option<String>,
    pub os_type: Option<String>,
    pub is_active: bool,
    pub is_blocked: bool,
    pub last_seen_at: String,
}

#[derive(Clone)]
pub struct ApiClient {
    client: Client,
    base_url: String,
    admin_key: String,
}

impl ApiClient {
    pub fn new(base_url: String, admin_key: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
            admin_key,
        }
    }

    async fn get(&self, endpoint: &str) -> Result<reqwest::Response> {
        let url = format!("{}/api/v1/admin{}", self.base_url, endpoint);
        let response = self.client
            .get(&url)
            .header("X-Admin-Key", &self.admin_key)
            .send()
            .await?;
        
        if !response.status().is_success() {
            anyhow::bail!("API request failed: {}", response.status());
        }
        
        Ok(response)
    }

    pub async fn get_system_stats(&self) -> Result<SystemStats> {
        let response = self.get("/stats").await?;
        let stats = response.json().await?;
        Ok(stats)
    }

    pub async fn list_clients(&self) -> Result<Vec<ClientInfo>> {
        let response = self.get("/clients").await?;
        let clients = response.json().await?;
        Ok(clients)
    }

    pub async fn list_devices(&self) -> Result<Vec<DeviceInfo>> {
        let response = self.get("/devices").await?;
        let devices = response.json().await?;
        Ok(devices)
    }

    #[allow(dead_code)]
    pub async fn block_device(&self, device_id: &str) -> Result<()> {
        let url = format!("{}/api/v1/admin/devices/{}/block", self.base_url, device_id);
        self.client
            .post(&url)
            .header("X-Admin-Key", &self.admin_key)
            .send()
            .await?;
        Ok(())
    }

    #[allow(dead_code)]
    pub async fn unblock_device(&self, device_id: &str) -> Result<()> {
        let url = format!("{}/api/v1/admin/devices/{}/unblock", self.base_url, device_id);
        self.client
            .post(&url)
            .header("X-Admin-Key", &self.admin_key)
            .send()
            .await?;
        Ok(())
    }
}
