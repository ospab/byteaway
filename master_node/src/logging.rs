use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn, error, debug};
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorMetrics {
    pub error_count: u64,
    pub last_error: Option<String>,
    pub last_error_time: Option<DateTime<Utc>>,
    pub errors_by_type: std::collections::HashMap<String, u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub request_count: u64,
    pub avg_response_time_ms: f64,
    pub active_connections: u64,
    pub memory_usage_mb: f64,
    pub cpu_usage_percent: f64,
}

#[derive(Clone)]
#[allow(dead_code)]
pub struct MetricsCollector {
    pub errors: Arc<RwLock<ErrorMetrics>>,
    pub performance: Arc<RwLock<PerformanceMetrics>>,
}

#[allow(dead_code)]
impl MetricsCollector {
    pub fn new() -> Self {
        Self {
            errors: Arc::new(RwLock::new(ErrorMetrics {
                error_count: 0,
                last_error: None,
                last_error_time: None,
                errors_by_type: std::collections::HashMap::new(),
            })),
            performance: Arc::new(RwLock::new(PerformanceMetrics {
                request_count: 0,
                avg_response_time_ms: 0.0,
                active_connections: 0,
                memory_usage_mb: 0.0,
                cpu_usage_percent: 0.0,
            })),
        }
    }

    pub async fn record_error(&self, error_type: &str, error_msg: &str) {
        let mut errors = self.errors.write().await;
        errors.error_count += 1;
        errors.last_error = Some(error_msg.to_string());
        errors.last_error_time = Some(Utc::now());
        *errors.errors_by_type.entry(error_type.to_string()).or_insert(0) += 1;
        
        error!("Error recorded: {} - {}", error_type, error_msg);
    }

    pub async fn record_request(&self, response_time_ms: f64) {
        let mut perf = self.performance.write().await;
        perf.request_count += 1;
        
        // Update running average
        let total_requests = perf.request_count as f64;
        perf.avg_response_time_ms = (perf.avg_response_time_ms * (total_requests - 1.0) + response_time_ms) / total_requests;
        
        debug!("Request recorded: {}ms, avg: {}ms", response_time_ms, perf.avg_response_time_ms);
    }

    pub async fn update_connection_count(&self, count: u64) {
        let mut perf = self.performance.write().await;
        perf.active_connections = count;
        info!("Active connections updated: {}", count);
    }

    pub async fn get_metrics(&self) -> (ErrorMetrics, PerformanceMetrics) {
        let errors = self.errors.read().await.clone();
        let performance = self.performance.read().await.clone();
        (errors, performance)
    }
}

pub fn setup_tracing(config: &crate::config::Config) -> anyhow::Result<()> {
    use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};
    
    let log_level = if config.debug_mode {
        "debug,sqlx=warn,master_node=debug,tokio=debug"
    } else {
        // Production: only info and above, suppress tokio worker logs
        "info,sqlx=warn,master_node=info,tokio=warn,tokio::net=warn,tokio::io=warn"
    };
    
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(log_level));

    tracing_subscriber::registry()
        .with(filter)
        .with(tracing_subscriber::fmt::layer()
            .with_target(config.debug_mode)
            .with_thread_ids(config.debug_mode)
            .with_thread_names(config.debug_mode)
            .with_file(config.debug_mode)
            .with_line_number(config.debug_mode))
        .init();

    info!("Logging initialized with level: {}", log_level);
    Ok(())
}

#[allow(dead_code)]
pub struct RequestLogger {
    request_id: String,
    start_time: std::time::Instant,
    method: String,
    path: String,
}

#[allow(dead_code)]
impl RequestLogger {
    pub fn new(method: &str, path: &str) -> Self {
        let request_id = Uuid::new_v4().to_string();
        let start_time = std::time::Instant::now();
        
        info!(
            request_id = %request_id,
            method = %method,
            path = %path,
            "Request started"
        );
        
        Self {
            request_id,
            start_time,
            method: method.to_string(),
            path: path.to_string(),
        }
    }
    
    pub fn finish(self, status: u16, metrics: Arc<MetricsCollector>) {
        let duration = self.start_time.elapsed().as_millis() as f64;
        
        let level = if status >= 500 {
            tracing::Level::ERROR
        } else if status >= 400 {
            tracing::Level::WARN
        } else {
            tracing::Level::INFO
        };
        
        match level {
            tracing::Level::ERROR => {
                error!(
                    request_id = %self.request_id,
                    method = %self.method,
                    path = %self.path,
                    status = status,
                    duration_ms = duration,
                    "Request completed with error"
                );
            }
            tracing::Level::WARN => {
                warn!(
                    request_id = %self.request_id,
                    method = %self.method,
                    path = %self.path,
                    status = status,
                    duration_ms = duration,
                    "Request completed with warning"
                );
            }
            _ => {
                info!(
                    request_id = %self.request_id,
                    method = %self.method,
                    path = %self.path,
                    status = status,
                    duration_ms = duration,
                    "Request completed"
                );
            }
        }
        
        // Record metrics asynchronously
        tokio::spawn(async move {
            metrics.record_request(duration).await;
            
            if status >= 400 {
                let error_type = if status >= 500 { "server_error" } else { "client_error" };
                metrics.record_error(error_type, &format!("{} {} {}", status, self.method, self.path)).await;
            }
        });
    }
}
