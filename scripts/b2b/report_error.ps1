# ByteAway B2B Error Reporting Script (PowerShell)
# Usage: .\report_error.ps1 -Token "API_TOKEN" -Message "Error message" -Context '{"extra": "data"}'

param (
    [Parameter(Mandatory=$true)]
    [string]$Token,

    [Parameter(Mandatory=$true)]
    [string]$Message,

    [string]$Context = "{}"
)

$headers = @{
    "Authorization" = "Bearer $Token"
    "Content-Type"  = "application/json"
}

$body = @{
    message = $Message
    context = $Context | ConvertFrom-Json
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "https://byteaway.xyz/api/v1/business/report-error" `
                      -Method Post `
                      -Headers $headers `
                      -Body $body
    Write-Host "Error reported successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to report error: $($_.Exception.Message)"
}
