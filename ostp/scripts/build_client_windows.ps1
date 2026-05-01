param(
    [ValidateSet("Debug", "Release")]
    [string]$Mode = "Release",
    [string]$Target = "x86_64-pc-windows-msvc"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

Write-Step "Repository root: $repoRoot"
Write-Step "Ensuring Rust target $Target is installed"
rustup target add $Target | Out-Host

$cargoArgs = @("build", "-p", "ostp-client", "--target", $Target)
if ($Mode -eq "Release") {
    $cargoArgs += "--release"
}

Write-Step "Building ostp-client ($Mode) for $Target"
& cargo @cargoArgs

if ($LASTEXITCODE -ne 0) {
    throw "cargo build failed"
}

$profileDir = if ($Mode -eq "Release") { "release" } else { "debug" }
$outDir = Join-Path $repoRoot "target\$Target\$profileDir"
$exePath = Join-Path $outDir "ostp-client.exe"

if (!(Test-Path $exePath)) {
    throw "Built executable not found: $exePath"
}

$configTemplate = Join-Path $repoRoot "ostp-client\ostp-client.toml.example"
$configPath = Join-Path $outDir "ostp-client.toml"

if (Test-Path $configTemplate) {
    if (!(Test-Path $configPath)) {
        Copy-Item $configTemplate $configPath
        Write-Step "Config deployed: $configPath"
    } else {
        Write-Step "Config preserved: $configPath"
    }
} else {
    Write-Warning "Config template not found: $configTemplate"
}

Write-Host ""
Write-Host "[DONE] Windows client build complete"
Write-Host "Executable: $exePath"
Write-Host "Config:     $configPath"
Write-Host ""
Write-Host "Run (headless):"
Write-Host "  $exePath --no-tui"
