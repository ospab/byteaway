use axum::{
    extract::State,
    http::{HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Extension, Json,
};
use serde_json::Value;
use std::sync::Arc;

use crate::auth::AuthContext;
use crate::error::AppError;
use crate::state::AppState;

pub async fn get_secure_manifest(
    State(state): State<Arc<AppState>>,
    Extension(_auth): Extension<AuthContext>,
) -> Result<Json<Value>, AppError> {
    let manifest_raw = tokio::fs::read_to_string(&state.app_update_manifest_path)
        .await
        .map_err(|e| AppError::Unexpected(anyhow::anyhow!("failed to read app update manifest: {}", e)))?;

    let mut manifest: Value = serde_json::from_str(manifest_raw.trim_start_matches('\u{feff}'))
        .map_err(|e| AppError::Unexpected(anyhow::anyhow!("invalid app update manifest json: {}", e)))?;

    let secure_apk_url = format!("{}/api/v1/app/update/apk", state.public_base_url.trim_end_matches('/'));

    if let Some(obj) = manifest.as_object_mut() {
        obj.insert("apk_url".to_string(), Value::String(secure_apk_url.clone()));
        if let Some(apk) = obj.get_mut("apk").and_then(Value::as_object_mut) {
            apk.insert("url".to_string(), Value::String(secure_apk_url));
        }
    }

    Ok(Json(manifest))
}

pub async fn download_secure_apk(
    Extension(_auth): Extension<AuthContext>,
) -> Result<impl IntoResponse, AppError> {
    let mut response = Response::new(axum::body::Body::empty());
    *response.status_mut() = StatusCode::OK;
    response.headers_mut().insert(
        "X-Accel-Redirect",
        HeaderValue::from_static("/_protected_downloads/byteaway-release.apk"),
    );
    response.headers_mut().insert(
        "Content-Type",
        HeaderValue::from_static("application/vnd.android.package-archive"),
    );
    response.headers_mut().insert(
        "Content-Disposition",
        HeaderValue::from_static("attachment; filename=byteaway-release.apk"),
    );
    response.headers_mut().insert(
        "Cache-Control",
        HeaderValue::from_static("no-store"),
    );

    Ok(response)
}
