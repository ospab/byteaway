use thiserror::Error;
use axum::response::{IntoResponse, Response};
use axum::http::StatusCode;

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
    
    #[error(transparent)]
    Unexpected(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, err_msg) = match self {
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "Unauthorized".to_string()),
            AppError::InsufficientBalance => (StatusCode::PAYMENT_REQUIRED, "Insufficient balance".to_string()),
            AppError::NodeOffline => (StatusCode::SERVICE_UNAVAILABLE, "Node offline".to_string()),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string()),
        };
        (status, err_msg).into_response()
    }
}
