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
        let (status, err_msg) = match self {
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::BadRequest(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::TooManyRequests => (StatusCode::TOO_MANY_REQUESTS, self.to_string()),
            AppError::InsufficientBalance => (StatusCode::PAYMENT_REQUIRED, self.to_string()),
            AppError::NodeOffline => (StatusCode::SERVICE_UNAVAILABLE, self.to_string()),
            AppError::Database(_) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Database: {}", self)),
            AppError::Redis(_) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Redis: {}", self)),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };
        (status, err_msg).into_response()
    }
}
