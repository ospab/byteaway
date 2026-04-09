use serde::Deserialize;

use crate::error::AppError;
use crate::state::AppState;

#[derive(Deserialize)]
struct TurnstileVerifyResponse {
    success: bool,
    #[serde(default, rename = "error-codes")]
    error_codes: Vec<String>,
}

pub async fn verify_turnstile_token(
    state: &AppState,
    token: &str,
    remote_ip: &str,
) -> Result<(), AppError> {
    if token.trim().is_empty() {
        return Err(AppError::BadRequest("captcha token is required".to_string()));
    }

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(8))
        .build()
        .map_err(|e| AppError::Unexpected(anyhow::anyhow!(e)))?;

    let response = client
        .post(&state.turnstile_verify_url)
        .form(&[
            ("secret", state.turnstile_secret_key.as_str()),
            ("response", token.trim()),
            ("remoteip", remote_ip),
        ])
        .send()
        .await
        .map_err(|e| AppError::Unexpected(anyhow::anyhow!("turnstile verification failed: {}", e)))?;

    if !response.status().is_success() {
        return Err(AppError::Unauthorized);
    }

    let payload: TurnstileVerifyResponse = response
        .json()
        .await
        .map_err(|e| AppError::Unexpected(anyhow::anyhow!("invalid turnstile response: {}", e)))?;

    if !payload.success {
        let detail = if payload.error_codes.is_empty() {
            "captcha verification failed".to_string()
        } else {
            format!("captcha verification failed: {}", payload.error_codes.join(","))
        };
        return Err(AppError::BadRequest(detail));
    }

    Ok(())
}
