# Mobile Application (Android / Flutter)

The ByteAway client application is designed to deliver high performance and a smooth user experience. It combines a flexible, cross-platform UI built with Flutter and low-level network operations provided by the Android OS.

## Flutter Layer (UI & Business Logic)

The source code is located in the `android/lib/` directory.

### Core Components and Structure
- **Routing (`app/router.dart`)**: Navigation is based on the `go_router` package. It features authentication checks (Auth Guard) and nested `StatefulShellRoute` paths for smooth tab transitions (Home, Statistics, Settings).
- **State Management (`presentation/*/`)**: The architecture is built around the BLoC/Cubit pattern. Key cubits:
  - `VpnCubit` – Handles starting, stopping, and fetching the current status of the VPN connection.
  - `SettingsCubit` – Manages user preferences, speed limits, and transport protocol choices.
  - `AuthCubit` – Responsible for token persistence and session statuses.
- **Data Access (`data/repositories/`)**: Encapsulates external API requests (`ApiClient`) and interacts with native platforms via `VpnRepositoryImpl`.

### Platform Channels

Platform channels facilitate data transmission between Dart and native Android code:

- **`com.byteaway.service` (MethodChannel)**: Accepts control commands such as `startVpn`, `stopVpn`, `startNode`, `stopNode`, and `getStatus`.
- **`com.byteaway.service/events` (EventChannel)**: Streams real-time status updates, including connection speed and errors.
- **`com.ospab.byteaway/app` (MethodChannel)**: Manages Split-Tunneling exception lists via `getInstalledApps`, `getExcludedApps`, `addExclude`, and `removeExclude`.

---

## Native Layer (Kotlin & C/Go)

The source code is located in the `android/android/app/src/main/kotlin/com/ospab/byteaway/` directory.

### 1. `ServiceBridge.kt`
Serves as the central bridge processing incoming requests from the Flutter layer:
- Requests system permissions to establish a VPN tunnel using the `VpnService.prepare()` API.
- Generates and forwards control commands via `Intents` to the `ByteAwayForegroundService`.
- Relays real-time metrics regarding connection status and bandwidth back to Dart.

### 2. `ByteAwayForegroundService.kt`
A persistent foreground service that operates independently of the application's visual lifecycle:
- **VPN Control**: Creates and configures the TUN interface via the native `VpnService.Builder`. Configures the IP address (`172.19.0.1`), MTU, and DNS settings. It enforces exception rules via `addDisallowedApplication`.
- **Traffic Loop Avoidance**: The application's own package name (`com.ospab.byteaway`) is systematically added to the exception list to ensure seamless background communication with the Master Node when the VPN is active.
- **Node Integration**: Manages and sustains the background connection (QUIC or WebSocket) to the Master Node for relaying client traffic.
- **Hysteria2 (HY2) Support**: Added integration for Hysteria2 as a testing/hidden VPN protocol. The `ByteAwayForegroundService.kt` includes a `wrapHy2ToJson()` function converting `hy2://` links into Sing-Box configs.

### 3. Sing-Box Go Integration
Network operations are managed using the `boxwrapper.aar` library, compiled with Go's `gomobile` tool.
- Incoming network traffic is directly passed from the Android TUN interface to the `sing-box` core using `Boxwrapper.startSingBox(jsonConfig)`.
- The configuration JSON is dynamically generated according to the current operational protocol (VLESS, Hysteria2 or OSTP) and active cryptographic keys. For Android compatibility, `"auto_detect_interface": false` is enforced in the configuration, and all DNS traffic is intercepted (`hijack-dns`) and routed to the DNS outbound.

---

## Build and Release Specifications

- **Automation Scripts**: Build processes are automated through the PowerShell script `build.ps1`, which compiles the Go modules, builds Flutter into a release-ready APK, and creates the OTA update manifest.
- **Obfuscation & ProGuard**: Obfuscation rules are defined in the `proguard-rules.pro` file. All classes under `boxwrapper.**` are explicitly excluded from stripping or renaming (`-keep class boxwrapper.** { *; }`) to prevent runtime JNI issues.
