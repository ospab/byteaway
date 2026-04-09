use crate::error::AppError;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use dashmap::DashMap;
use tokio::sync::mpsc;
use uuid::Uuid;
use tracing::{info, debug};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct NodeMetadata {
    pub node_id: Uuid,
    pub ip_address: std::net::IpAddr,
    pub country: String,
    pub connection_type: ConnectionType,
    pub speed_mbps: u32,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
pub enum ConnectionType {
    WiFi,
    Mobile,
}

/// Команды, которые роутер посылает в WebSocket-хендлер конкретной ноды
pub enum WsCommand {
    /// Открыть туннель к целевому адресу
    Open {
        session_id: Uuid,
        target_addr: String,
        /// Канал для отправки данных ОТ мобильной ноды обратно в SOCKS5 клиент
        reply_tx: mpsc::Sender<Vec<u8>>,
    },
    /// Передать данные в открытый туннель
    Data {
        session_id: Uuid,
        payload: Vec<u8>,
    },
    /// Закрыть туннель
    Close {
        session_id: Uuid,
    },
}

/// Живое WS-соединение с мобильной нодой, хранится в DashMap
pub struct ActiveConnection {
    pub tx: mpsc::Sender<WsCommand>,
    pub meta: NodeMetadata,
    pub active_sessions: AtomicU32,
}

#[async_trait::async_trait]
pub trait NodeRegistry: Send + Sync {
    async fn register_node(&self, meta: NodeMetadata, tx: mpsc::Sender<WsCommand>) -> Result<(), AppError>;
    async fn remove_node(&self, node_id: Uuid, country: &str) -> Result<(), AppError>;
    async fn find_node(&self, country: Option<&str>, conn_type: Option<ConnectionType>) -> Result<Uuid, AppError>;
    async fn heartbeat(&self, node_id: Uuid) -> Result<(), AppError>;
}

pub struct RedisNodeRegistry {
    pub redis_client: redis::Client,
    pub active_connections: Arc<DashMap<Uuid, ActiveConnection>>,
}

impl RedisNodeRegistry {
    pub fn new(redis_url: &str) -> Result<Self, AppError> {
        let client = redis::Client::open(redis_url).map_err(AppError::Redis)?;
        Ok(Self {
            redis_client: client,
            active_connections: Arc::new(DashMap::new()),
        })
    }

    fn live_key(node_id: Uuid) -> String {
        format!("node:live:{}", node_id)
    }

    fn country_set_key(country: &str) -> String {
        format!("nodes:by_country:{}", country)
    }
}

#[async_trait::async_trait]
impl NodeRegistry for RedisNodeRegistry {
    async fn register_node(&self, meta: NodeMetadata, tx: mpsc::Sender<WsCommand>) -> Result<(), AppError> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await.map_err(AppError::Redis)?;

        let meta_json = serde_json::to_string(&meta)
            .map_err(|e| AppError::Unexpected(anyhow::anyhow!(e)))?;
        let live_key = Self::live_key(meta.node_id);
        let country_key = Self::country_set_key(&meta.country);

        let _: () = redis::pipe()
            .atomic()
            .set_ex(&live_key, meta_json, 60)
            .sadd(&country_key, meta.node_id.to_string())
            .query_async(&mut conn)
            .await
            .map_err(AppError::Redis)?;

        self.active_connections.insert(meta.node_id, ActiveConnection {
            tx,
            meta: meta.clone(),
            active_sessions: AtomicU32::new(0),
        });

        info!("Node {} registered [{}] country={}", meta.node_id, 
              if meta.connection_type == ConnectionType::WiFi { "WiFi" } else { "Mobile" },
              meta.country);
        Ok(())
    }

    async fn remove_node(&self, node_id: Uuid, country: &str) -> Result<(), AppError> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await.map_err(AppError::Redis)?;

        let _: () = redis::pipe()
            .atomic()
            .del(Self::live_key(node_id))
            .srem(Self::country_set_key(country), node_id.to_string())
            .query_async(&mut conn)
            .await
            .map_err(AppError::Redis)?;

        self.active_connections.remove(&node_id);
        info!("Node {} removed", node_id);
        Ok(())
    }

    /// Находит наименее загруженную ноду по стране и типу соединения
    async fn find_node(&self, country: Option<&str>, conn_type: Option<ConnectionType>) -> Result<Uuid, AppError> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await.map_err(AppError::Redis)?;

        let mut candidates: Vec<String> = if let Some(c) = country {
            conn.smembers(Self::country_set_key(c)).await.map_err(AppError::Redis)?
        } else {
            // Если страна не указана, берём все ноды из памяти
            self.active_connections.iter().map(|e| e.key().to_string()).collect()
        };

        // Fallback: if no nodes in requested country, try any live node.
        if candidates.is_empty() {
            candidates = self.active_connections.iter().map(|e| e.key().to_string()).collect();
        }

        if candidates.is_empty() {
            return Err(AppError::NodeOffline);
        }

        // Выбираем наименее загруженную ноду
        let mut best: Option<(Uuid, u32)> = None;

        for cid in candidates {
            let nid = match Uuid::parse_str(&cid) {
                Ok(id) => id,
                Err(_) => continue,
            };

            // Проверяем жива ли нода в Redis
            let is_live: bool = conn.exists(Self::live_key(nid)).await.unwrap_or(false);
            if !is_live {
                // Если в Redis нет, а в Set или DashMap есть — чистим (лениво)
                if let Some(c) = country {
                    let _: () = conn.srem(Self::country_set_key(c), &cid).await.unwrap_or_default();
                }
                continue;
            }

            if let Some(entry) = self.active_connections.get(&nid) {
                // Фильтр по типу соединения
                if let Some(ref ct) = conn_type {
                    if entry.meta.connection_type != *ct {
                        continue;
                    }
                }
                let sessions = entry.active_sessions.load(Ordering::Relaxed);
                if best.is_none() || sessions < best.unwrap().1 {
                    best = Some((nid, sessions));
                }
            }
        }

        best.map(|(id, _)| id).ok_or(AppError::NodeOffline)
    }

    async fn heartbeat(&self, node_id: Uuid) -> Result<(), AppError> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await.map_err(AppError::Redis)?;
        let exists: bool = conn.expire(Self::live_key(node_id), 60).await.map_err(AppError::Redis)?;
        if !exists {
            return Err(AppError::NodeOffline);
        }
        debug!("Heartbeat for node {}", node_id);
        Ok(())
    }
}
