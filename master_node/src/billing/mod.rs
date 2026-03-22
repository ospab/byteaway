pub mod engine;

use crate::error::AppError;
use uuid::Uuid;

#[async_trait::async_trait]
pub trait BillingEngine: Send + Sync {
    /// Резервирует небольшую сумму/трафик перед началом сессии
    async fn reserve_balance(&self, client_id: Uuid, est_bytes: u64) -> Result<(), AppError>;
    
    /// Фиксирует потребленный трафик в Redis (вызывается из SOCKS5 стрима)
    async fn commit_usage(&self, client_id: Uuid, node_id: Uuid, bytes: u64) -> Result<(), AppError>;
    
    /// Фоновый процесс (воркер). Берет накопившийся `traffic:client:*`, 
    /// списывает баланс в Postgres и пишет в `traffic_history`.
    async fn process_redis_flush(&self) -> Result<(), AppError>;
}
