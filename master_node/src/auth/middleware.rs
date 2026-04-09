use axum::{
    extract::{Request, State},
    middleware::Next,
    response::Response,
};
use std::sync::Arc;
use crate::state::AppState;
use crate::error::AppError;
use tracing::warn;

/// Axum middleware: извлекает Bearer токен из заголовка Authorization,
/// аутентифицирует клиента и кладёт AuthContext в request extensions.
pub async fn require_auth(
    State(state): State<Arc<AppState>>,
    axum::extract::ConnectInfo(addr): axum::extract::ConnectInfo<std::net::SocketAddr>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = req
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| {
            warn!("Missing Authorization header");
            AppError::Unauthorized
        })?;

    let api_key = auth_header
        .strip_prefix("Bearer ")
        .ok_or(AppError::Unauthorized)?;

    let context = state.authenticator.authenticate(api_key, &addr.ip().to_string()).await?;
    req.extensions_mut().insert(context);


    Ok(next.run(req).await)
}
