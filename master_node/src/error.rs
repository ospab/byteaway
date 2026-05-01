use thiserror::Error;
use axum::response::{IntoResponse, Response};
use axum::http::StatusCode;
use tracing;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
    
    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),
    
    #[error("Insufficient balance")]
    InsufficientBalance,
    
    #[error("Node not found or offline")]
    NodeOffline,
    
    #[error("Authentication failed")]
    Unauthorized,

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Too many requests")]
    TooManyRequests,
    
    #[error(transparent)]
    Unexpected(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        tracing::error!("API Error: {:?}", self);
        
        let (status, err_code, err_msg): (StatusCode, &'static str, String) = match self {
            AppError::Unauthorized => (
                StatusCode::UNAUTHORIZED, 
                "AUTH_FAILED", 
                "Authentication failed. Check your API key or device token.".to_string()
            ),
            AppError::BadRequest(msg) => (
                StatusCode::BAD_REQUEST, 
                "BAD_REQUEST", 
                format!("Bad request: {}", msg)
            ),
            AppError::TooManyRequests => (
                StatusCode::TOO_MANY_REQUESTS, 
                "RATE_LIMIT", 
                "Too many requests. Please retry after a short delay.".to_string()
            ),
            AppError::InsufficientBalance => (
                StatusCode::PAYMENT_REQUIRED, 
                "LOW_BALANCE", 
                "Insufficient balance. Please top up your account to continue.".to_string()
            ),
            AppError::NodeOffline => (
                StatusCode::SERVICE_UNAVAILABLE, 
                "NODES_OFFLINE", 
                "No residential nodes available in the selected region.".to_string()
            ),
            AppError::Database(_) => (
                StatusCode::INTERNAL_SERVER_ERROR, 
                "DB_ERROR", 
                "Internal database error.".to_string()
            ),
            AppError::Redis(_) => (
                StatusCode::INTERNAL_SERVER_ERROR, 
                "CACHE_ERROR", 
                "Internal cache synchronization error.".to_string()
            ),
            _ => (
                StatusCode::INTERNAL_SERVER_ERROR, 
                "INTERNAL_ERROR", 
                "An unexpected internal error occurred.".to_string()
            ),
        };

        let body = serde_json::json!({
            "status": "error",
            "code": err_code,
            "message": err_msg,
        });

        (status, axum::Json(body)).into_response()
    }
}
