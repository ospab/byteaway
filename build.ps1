<#
.SYNOPSIS
    ByteAway App Full Build Script (Windows)
.DESCRIPTION
    Compiles Go-core boxwrapper (sing-box), builds Flutter APK and moves it to builded folder.
#>

param (
    [string]$BuildType = "debug",
    [ValidateSet("none", "local", "scp")]
    [string]$PublishMode = "none",
    [string]$PublicBaseUrl = "https://byteaway.xyz",
    [string]$LocalWebPublicDir = "",
    [string]$RemoteUser = "",
    [string]$RemoteHost = "",
    [string]$RemotePath = "",
    [int]$RemotePort = 22,
    [string]$SshKeyPath = "",
    [string]$SitePublicDir = "",
    [bool]$AutoBumpVersionCode = $true,
    [ValidateSet("universal", "arm64")]
    [string]$ReleaseApkVariant = "universal",
    [int]$MinimumSupportedBuild = 1,
    [int]$GomobileTimeoutMinutes = 30,
    [int]$GomobileNoOutputTimeoutMinutes = 6,
    [string]$ChangelogMessage = "Стабилизация узла, улучшения биллинга и автообновление приложения."
)

if ($BuildType -notmatch "^(debug|release)$") {
    Write-Error "BuildType must be 'debug' or 'release'"
    exit 1
}

Write-Host "=== Starting ByteAway Build ($BuildType) ===" -ForegroundColor Cyan

# 1. Determine if we need to compile Go Core
$GoCorePath = Join-Path $PSScriptRoot "android\go_core"
$LibsDir = Join-Path $PSScriptRoot "android\android\app\libs"
if (-not (Test-Path $LibsDir)) { New-Item -ItemType Directory -Force -Path $LibsDir | Out-Null }
$AarPath = Join-Path $LibsDir "boxwrapper.aar"

$NeedGoBuild = $true
$LatestGoModTime = [datetime]::MinValue
if (Test-Path $AarPath) {
    $GoCoreFiles = Get-ChildItem -Path $GoCorePath -Recurse -File | Where-Object { $_.Extension -match "\.(go|mod|sum)$" }
    if ($GoCoreFiles) {
        $LatestGoModTime = ($GoCoreFiles | Measure-Object -Property LastWriteTime -Maximum).Maximum
        $AarModTime = (Get-Item $AarPath).LastWriteTime
        if ($AarModTime -ge $LatestGoModTime) {
            $NeedGoBuild = $false
        }
    }
}

# 2. Determine if we need to build Flutter
$ApkSource = if ($BuildType -eq "release") { Join-Path $PSScriptRoot "android\build\app\outputs\flutter-apk\app-release.apk" } else { Join-Path $PSScriptRoot "android\build\app\outputs\flutter-apk\app-debug.apk" }
$NeedFlutterBuild = $true

if (Test-Path $ApkSource) {
    if (-not $NeedGoBuild) {
        $ApkModTime = (Get-Item $ApkSource).LastWriteTime
        $FlutterSourceDirs = @(
            (Join-Path $PSScriptRoot "android\lib")
            (Join-Path $PSScriptRoot "android\android\app\src")
            (Join-Path $PSScriptRoot "android\pubspec.yaml")
        )
        $LatestFlutterModTime = [datetime]::MinValue
        foreach ($dir in $FlutterSourceDirs) {
            if (Test-Path $dir) {
                $files = Get-ChildItem -Path $dir -Recurse -File
                if ($files) {
                    $max = ($files | Measure-Object -Property LastWriteTime -Maximum).Maximum
                    if ($max -gt $LatestFlutterModTime) {
                        $LatestFlutterModTime = $max
                    }
                }
            }
        }
        
        if ($LatestGoModTime -gt $LatestFlutterModTime) {
            $LatestFlutterModTime = $LatestGoModTime
        }
        
        if ($ApkModTime -ge $LatestFlutterModTime) {
            $NeedFlutterBuild = $false
        }
    }
}
# Auto-bump Flutter versionName + versionCode in pubspec for release builds.
if ($BuildType -eq "release" -and $AutoBumpVersionCode -and $NeedFlutterBuild) {
    $PubspecPath = Join-Path $PSScriptRoot "android\pubspec.yaml"
    if (Test-Path $PubspecPath) {
        $content = Get-Content $PubspecPath -Raw
        $pattern = 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)'
        $m = [regex]::Match($content, $pattern)
        if ($m.Success) {
            $versionName = $m.Groups[1].Value
            $parts = $versionName.Split('.')
            $major = [int]$parts[0]
            $minor = [int]$parts[1]
            $patch = [int]$parts[2]
            $nextVersionName = "$major.$minor.$($patch + 1)"
            $currentCode = [int]$m.Groups[2].Value
            $nextCode = $currentCode + 1
            $newVersion = "version: $nextVersionName+$nextCode"
            $content = [regex]::Replace($content, $pattern, $newVersion, 1)
            Set-Content -Path $PubspecPath -Value $content -Encoding UTF8
            Write-Host "Auto-bumped app version: $versionName+$currentCode -> $nextVersionName+$nextCode" -ForegroundColor Green

            $ConstantsPath = Join-Path $PSScriptRoot "android\lib\core\constants.dart"
            if (Test-Path $ConstantsPath) {
                $constantsRaw = Get-Content $ConstantsPath -Raw
                $constantsRaw = [regex]::Replace($constantsRaw, "static const String appVersion = '[^']+';", "static const String appVersion = '$nextVersionName';", 1)
                $constantsRaw = [regex]::Replace($constantsRaw, "static const int appBuildNumber = [0-9]+;", "static const int appBuildNumber = $nextCode;", 1)
                Set-Content -Path $ConstantsPath -Value $constantsRaw -Encoding UTF8
                Write-Host "Synced app constants version to $nextVersionName+$nextCode" -ForegroundColor Green
            }
        } else {
            Write-Warning "Could not parse version from pubspec.yaml; auto-bump skipped"
        }
    } else {
        Write-Warning "pubspec.yaml not found; auto-bump skipped"
    }
}

# 1. Build Go wrapper
Write-Host "`n[1/3] Compiling boxwrapper.aar using gomobile..." -ForegroundColor Yellow
if (-not (Test-Path $GoCorePath)) {
    Write-Error "Folder $GoCorePath not found!"
    exit 1
}
Set-Location $GoCorePath

if (-not $NeedGoBuild) {
    Write-Host "OK: boxwrapper.aar is up to date, skipping gomobile compile." -ForegroundColor Green
} else {
    Write-Host "Running go mod tidy..." -ForegroundColor Gray
    go get golang.org/x/mobile/bind 2>&1 | Out-Null
    go mod tidy

# Auto-detect Android NDK for gomobile
$AndroidHome = $env:ANDROID_HOME
if (-not $AndroidHome) {
    if ($env:LOCALAPPDATA) {
        $AndroidHome = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    } else {
        $AndroidHome = "D:\Toolz\android-sdk"
    }
}

$NdkDir = Join-Path $AndroidHome "ndk"
if (Test-Path $NdkDir) {
    $LatestNdk = Get-ChildItem -Path $NdkDir -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($LatestNdk) {
        $env:ANDROID_NDK_HOME = $LatestNdk.FullName
        Write-Host "Auto-detected NDK: $($env:ANDROID_NDK_HOME)" -ForegroundColor DarkGray
    }
}



# Override temp folder to avoid "No space left on device" if C: drive is full
$CustomTemp = Join-Path $PSScriptRoot "android\go_core\.tmp"
if (-not (Test-Path $CustomTemp)) {
    New-Item -ItemType Directory -Force -Path $CustomTemp | Out-Null
}
$env:TMP = $CustomTemp
$env:TEMP = $CustomTemp

# Force garbage collection limits to prevent Windows Pagefile exhaustion (errno 1455 OOM)
$env:GOMEMLIMIT = "1400MiB"
$env:GOGC = "30"
$env:GOMAXPROCS = "1"
$env:GOFLAGS = "-p=1"

# Build release with arm64 only to reduce peak memory usage.
# If it still fails due low virtual memory, retry with extra conservative settings.
$GoBindTargets = if ($BuildType -eq "release") { "android/arm64" } else { "android/arm64,android/amd64" }

function Invoke-GomobileBind {
    param (
        [string]$Targets,
        [string]$MemLimit,
        [string]$GcValue,
        [string]$PackagePath
    )

    $env:GOMEMLIMIT = $MemLimit
    $env:GOGC = $GcValue
    Write-Host "gomobile targets: $Targets | GOMEMLIMIT=$MemLimit | GOGC=$GcValue | GOMAXPROCS=$($env:GOMAXPROCS)" -ForegroundColor DarkGray

    # Keep all linker flags inside one quoted -ldflags argument.
    $ldflags = '-w -s -checklinkname=0'

    $gomobileArgs = @(
        "bind",
        "-target=$($Targets)",
        "-androidapi", "21",
        "-v",
        "-o", "$AarPath",
        "$PackagePath"
    )

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $gomobileOutLogPath = Join-Path $CustomTemp "gomobile-bind-$stamp.stdout.log"
    $gomobileErrLogPath = Join-Path $CustomTemp "gomobile-bind-$stamp.stderr.log"
    foreach ($logPath in @($gomobileOutLogPath, $gomobileErrLogPath)) {
        if (Test-Path $logPath) {
            Remove-Item $logPath -Force -ErrorAction SilentlyContinue
        }
    }

    $proc = Start-Process -FilePath "gomobile" -ArgumentList $gomobileArgs -NoNewWindow -PassThru -RedirectStandardOutput $gomobileOutLogPath -RedirectStandardError $gomobileErrLogPath

    $timeoutSec = [Math]::Max(60, $GomobileTimeoutMinutes * 60)
    $noOutputTimeoutSec = [Math]::Max(30, $GomobileNoOutputTimeoutMinutes * 60)
    $startAt = Get-Date
    $lastOutSize = -1
    $lastErrSize = -1
    $lastOutputAt = Get-Date

    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 5

        $elapsedSec = [int]((Get-Date) - $startAt).TotalSeconds
        $silenceSec = [int]((Get-Date) - $lastOutputAt).TotalSeconds

        $hadOutput = $false

        if (Test-Path $gomobileOutLogPath) {
            $outSize = (Get-Item $gomobileOutLogPath).Length
            if ($outSize -ne $lastOutSize) {
                $lastOutSize = $outSize
                $hadOutput = $true
            }
        }
        if (Test-Path $gomobileErrLogPath) {
            $errSize = (Get-Item $gomobileErrLogPath).Length
            if ($errSize -ne $lastErrSize) {
                $lastErrSize = $errSize
                $hadOutput = $true
            }
        }

        if ($hadOutput) {
            $lastOutputAt = Get-Date
            Write-Host "gomobile bind progress: elapsed ${elapsedSec}s" -ForegroundColor DarkGray
        }

        if ($elapsedSec -ge $timeoutSec) {
            Write-Warning "gomobile bind exceeded timeout (${GomobileTimeoutMinutes} min). Terminating process..."
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            break
        }

        if ($silenceSec -ge $noOutputTimeoutSec) {
            Write-Warning "gomobile bind produced no output for ${GomobileNoOutputTimeoutMinutes} min. Terminating process..."
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            break
        }
    }

    try { $proc.WaitForExit() } catch {}

    $combinedOutput = @()
    if (Test-Path $gomobileOutLogPath) {
        $combinedOutput += Get-Content -Path $gomobileOutLogPath
    }
    if (Test-Path $gomobileErrLogPath) {
        $combinedOutput += Get-Content -Path $gomobileErrLogPath
    }

    if ($combinedOutput.Count -gt 0) {
        $script:lastGomobileOutput = $combinedOutput
        $script:lastGomobileOutput | Select-Object -Last 120 | Write-Host
    } else {
        $script:lastGomobileOutput = @("gomobile log files were not created")
    }

    return ($proc.ExitCode -eq 0)
}

$lastGomobileOutput = @()
$bindOk = Invoke-GomobileBind -Targets $GoBindTargets -MemLimit "1400MiB" -GcValue "30" "./boxwrapper"
if (-not $bindOk) {
    if (Test-Path $AarPath) {
        $AarModTimeNow = (Get-Item $AarPath).LastWriteTime
        if ($AarModTimeNow -gt (Get-Date).AddMinutes(-10)) {
            Write-Host "Warning: gomobile bind returned non-zero code, but boxwrapper.aar was created/updated. Proceeding..." -ForegroundColor Yellow
            $bindOk = $true
        }
    }
}

if (-not $bindOk) {
    $gomobileLog = ($lastGomobileOutput | Out-String)
    $isPagingFileError = $gomobileLog -match "paging file is too small|operation to complete|errno 1455"

    if ($isPagingFileError) {
        Write-Warning "Detected low virtual memory during gomobile bind. Retrying with stricter memory settings..."
        $bindOk = Invoke-GomobileBind -Targets "android/arm64" -MemLimit "1024MiB" -GcValue "20" "./boxwrapper"
    }
}

if (-not $bindOk) {
    Write-Error "Error compiling Go library! Ensure gomobile is installed and Android NDK is present."
    exit 1
}
Write-Host "OK: boxwrapper.aar successfully compiled." -ForegroundColor Green
}

# 2. Build Flutter app
Write-Host "`n[2/3] Building Flutter APK..." -ForegroundColor Yellow

if (-not $NeedFlutterBuild) {
    Write-Host "OK: Flutter APK is up to date, skipping compilation." -ForegroundColor Green
} else {
    $AndroidPath = Join-Path $PSScriptRoot "android"
    Set-Location $AndroidPath

    $flutterBuildExit = 0

    if ($BuildType -eq "release") {
        if ($ReleaseApkVariant -eq "arm64") {
            Write-Host "Building arm64-only release APK for smaller OTA downloads..." -ForegroundColor Gray
            flutter build apk --release --target-platform android-arm64
            $flutterBuildExit = $LASTEXITCODE
        } else {
            Write-Host "Building universal release APK..." -ForegroundColor Gray
            flutter build apk --release
            $flutterBuildExit = $LASTEXITCODE
        }
    } else {
        flutter build apk --debug
        $flutterBuildExit = $LASTEXITCODE
    }

    if ($flutterBuildExit -ne 0) {
        Write-Error "Error building Flutter app!"
        exit 1
    }
    Write-Host "OK: Flutter APK successfully built." -ForegroundColor Green
}

# 3. Move artifact
Write-Host "`n[3/3] Moving compiled APK to \builded..." -ForegroundColor Yellow
Set-Location $PSScriptRoot

$BuildedDir = Join-Path $PSScriptRoot "builded"
if (-not (Test-Path $BuildedDir)) {
    New-Item -ItemType Directory -Force -Path $BuildedDir | Out-Null
}

if ($BuildType -eq "release") {
    $ApkSource = Join-Path $PSScriptRoot "android\build\app\outputs\flutter-apk\app-release.apk"
    $ApkDest = Join-Path $BuildedDir "byteaway-release.apk"
} else {
    $ApkSource = Join-Path $PSScriptRoot "android\build\app\outputs\flutter-apk\app-debug.apk"
    $ApkDest = Join-Path $BuildedDir "byteaway-debug.apk"
}

if (Test-Path $ApkSource) {
    Copy-Item -Path $ApkSource -Destination $ApkDest -Force
    Write-Host "SUCCESS! Build complete." -ForegroundColor Green
    Write-Host "APK path: $ApkDest" -ForegroundColor Cyan
} else {
    Write-Error "APK not found at path: $ApkSource"
    exit 1
}

if ($BuildType -eq "release") {
    Write-Host "`n[4/4] Preparing OTA artifacts..." -ForegroundColor Yellow

    $VersionName = "1.0.0"
    $VersionCode = 1
    $PubspecPath = Join-Path $PSScriptRoot "android\pubspec.yaml"
    if (Test-Path $PubspecPath) {
        $VersionLine = (Get-Content $PubspecPath | Where-Object { $_ -match '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)' } | Select-Object -First 1)
        if ($VersionLine -and ($VersionLine -match '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)')) {
            $VersionName = $Matches[1]
            $VersionCode = [int]$Matches[2]
        }
    }

    $ArtifactsRoot = Join-Path $BuildedDir "updates"
    $ArtifactsDownloads = Join-Path $ArtifactsRoot "downloads"
    New-Item -ItemType Directory -Force -Path $ArtifactsDownloads | Out-Null

    $PublishedApkPath = Join-Path $ArtifactsDownloads "byteaway-release.apk"
    Copy-Item -Path $ApkSource -Destination $PublishedApkPath -Force

    $ApkFileInfo = Get-Item $PublishedApkPath
    $ApkSizeBytes = [int64]$ApkFileInfo.Length
    $ApkSha256 = (Get-FileHash -Path $PublishedApkPath -Algorithm SHA256).Hash.ToLower()

    $BaseUri = [Uri]$PublicBaseUrl
    $AllowedHost = $BaseUri.Host
    $PublishedAt = (Get-Date).ToUniversalTime().ToString("o")
    $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(30).ToString("o")
    $SecurityNonce = [guid]::NewGuid().ToString("N")

    $ReleaseNotes = $ChangelogMessage -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($ReleaseNotes.Count -eq 0) {
        $ReleaseNotes = @($ChangelogMessage)
    }

    $MandatoryUpdate = $VersionCode -le $MinimumSupportedBuild

    $Manifest = @{
        schema_version = 2
        app_id = "com.ospab.byteaway"
        channel = "stable"
        version = $VersionName
        build_number = $VersionCode
        min_supported_build = $MinimumSupportedBuild
        apk_url = "$($PublicBaseUrl.TrimEnd('/'))/downloads/byteaway-release.apk"
        apk_sha256 = $ApkSha256
        apk_size_bytes = $ApkSizeBytes
        release_notes = $ReleaseNotes
        rollout = @{
            percentage = 100
            cohort = "all"
        }
        apk = @{
            url = "$($PublicBaseUrl.TrimEnd('/'))/downloads/byteaway-release.apk"
            sha256 = $ApkSha256
            size_bytes = $ApkSizeBytes
            mime_type = "application/vnd.android.package-archive"
            abi = if ($ReleaseApkVariant -eq "arm64") { "arm64-v8a" } else { "universal" }
            min_sdk = 21
        }
        security = @{
            requires_https = $true
            allowed_hosts = @($AllowedHost)
            anti_rollback = $true
            issued_at = $PublishedAt
            expires_at = $ExpiresAt
            nonce = $SecurityNonce
        }
        changelog = $ChangelogMessage
        mandatory = $MandatoryUpdate
        published_at = $PublishedAt
    } | ConvertTo-Json -Depth 5

    $ManifestPath = Join-Path $ArtifactsDownloads "android.json"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ManifestPath, $Manifest, $utf8NoBom)

    Write-Host "Prepared APK artifact: $PublishedApkPath" -ForegroundColor Green
    Write-Host "Prepared manifest: $ManifestPath" -ForegroundColor Green


    # Always prepare a website-ready payload folder to copy as-is to a web host.
    $SitePayloadRoot = Join-Path $BuildedDir "site_update_payload"
    $SitePayloadPublic = Join-Path $SitePayloadRoot "public"
    $SitePayloadDownloads = Join-Path $SitePayloadPublic "downloads"

    New-Item -ItemType Directory -Force -Path $SitePayloadDownloads | Out-Null

    Copy-Item -Path $PublishedApkPath -Destination (Join-Path $SitePayloadDownloads "byteaway-release.apk") -Force
    Copy-Item -Path $ManifestPath -Destination (Join-Path $SitePayloadDownloads "android.json") -Force

    # Include built frontend in payload to avoid accidental deployment of Vite source index.html
    $BuiltWebDist = Join-Path $PSScriptRoot "web\dist"
    if (Test-Path $BuiltWebDist) {
        Copy-Item -Path (Join-Path $BuiltWebDist "*") -Destination $SitePayloadPublic -Recurse -Force
        Write-Host "Included web/dist in site payload." -ForegroundColor Green
    } else {
        Write-Warning "web/dist not found. Build frontend (cd web; npm run build) before deploying site payload."
    }

    $DeployReadme = @"
Copy the contents of this folder into your website public root.

Required files:
- public/index.html (from web/dist)
- public/assets/* (from web/dist)
- public/downloads/byteaway-release.apk
- public/downloads/android.json

Important:
- Do NOT deploy web/index.html from source, because it references /src/main.tsx.
- Production must serve the built index.html generated by Vite from web/dist.
"@
    Set-Content -Path (Join-Path $SitePayloadRoot "README.txt") -Value $DeployReadme -Encoding UTF8

    Write-Host "Prepared site payload: $SitePayloadRoot" -ForegroundColor Green

    if ($PublishMode -eq "local") {
        $TargetWebPublic = if ([string]::IsNullOrWhiteSpace($LocalWebPublicDir)) {
            Join-Path $PSScriptRoot "web\public"
        } else {
            $LocalWebPublicDir
        }

        if (Test-Path $TargetWebPublic) {
            $LocalDownloads = Join-Path $TargetWebPublic "downloads"
            New-Item -ItemType Directory -Force -Path $LocalDownloads | Out-Null

            Copy-Item -Path $PublishedApkPath -Destination (Join-Path $LocalDownloads "byteaway-release.apk") -Force
            Copy-Item -Path $ManifestPath -Destination (Join-Path $LocalDownloads "android.json") -Force
            Write-Host "Published to local web/public: $TargetWebPublic" -ForegroundColor Green
        } else {
            Write-Warning "Local publish skipped: web/public path not found: $TargetWebPublic"
        }
    } elseif ($PublishMode -eq "scp") {
        if ([string]::IsNullOrWhiteSpace($RemoteUser) -or [string]::IsNullOrWhiteSpace($RemoteHost) -or [string]::IsNullOrWhiteSpace($RemotePath)) {
            Write-Warning "SCP publish skipped: set -RemoteUser, -RemoteHost, -RemotePath"
        } else {
            $ScpBaseArgs = @("-P", "$RemotePort")
            if (-not [string]::IsNullOrWhiteSpace($SshKeyPath)) {
                $ScpBaseArgs += @("-i", $SshKeyPath)
            }

            $RemoteDownloads = "$RemoteUser@$RemoteHost`:$RemotePath/downloads/byteaway-release.apk"
            $RemoteManifest = "$RemoteUser@$RemoteHost`:$RemotePath/downloads/android.json"

            & scp @ScpBaseArgs $PublishedApkPath $RemoteDownloads
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "SCP upload failed for APK"
            }

            & scp @ScpBaseArgs $ManifestPath $RemoteManifest
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "SCP upload failed for manifest"
            } else {
                Write-Host "Published to remote host via SCP: $RemoteHost" -ForegroundColor Green
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SitePublicDir)) {
        if (Test-Path $SitePublicDir) {
            $SiteDownloads = Join-Path $SitePublicDir "downloads"
            New-Item -ItemType Directory -Force -Path $SiteDownloads | Out-Null

            Copy-Item -Path $PublishedApkPath -Destination (Join-Path $SiteDownloads "byteaway-release.apk") -Force
            Copy-Item -Path $ManifestPath -Destination (Join-Path $SiteDownloads "android.json") -Force
            Write-Host "Synced OTA files to site public dir: $SitePublicDir" -ForegroundColor Green
        } else {
            Write-Warning "SitePublicDir not found, sync skipped: $SitePublicDir"
        }
    }
}
