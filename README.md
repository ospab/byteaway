# ByteAway: Enterprise Proxy & VPN Infrastructure

ByteAway is an advanced, distributed network solution designed to provide reliable high-speed VPN services while orchestrating a residential proxy mesh network. The platform enables users to securely bypass internet restrictions using state-of-the-art protocols, and allows voluntary bandwidth contribution to a B2B proxy pool.

---

## Technical Overview

### 1. Client Architecture (Android / Flutter)
- **High-Performance UI Engine**: Built with Flutter 3 using premium Glassmorphism design tokens and Material 3 design patterns.
- **DPI-Resistant Routing Engine**: Supports VLESS (XTLS-Reality), OSTP (Ospab Stealth Transport Protocol), and Hysteria2 to securely bypass deep packet inspection filters.
- **Enterprise-Grade TUN Layer**: Native Android `VpnService` with direct file descriptor injection into the custom Sing-Box Go core via gomobile.
- **Residential Node Sharing**: Provides cross-platform WebSocket and QUIC traffic relay from mobile nodes to B2B users via a decentralized routing infrastructure.

### 2. Infrastructure Layer (Rust Master Node)
- **Low-Latency Orchestration**: High-performance backend written entirely in asynchronous Rust.
- **Multiprotocol Proxy Ingress**: Accepts client traffic through SOCKS5 and HTTP protocols, routing it to the most geographically optimal mobile node.
- **Real-Time Traffic Accounting**: High-precision Redis-based billing engine with transactional flush routines to PostgreSQL.
- **Dynamic Policy Routing**: Dynamic configuration generation and distribution through a REST API.

---

## Project Organization

```text
├── android          # Source code for the mobile client (Flutter, Kotlin, Go)
├── master_node      # High-throughput orchestration and billing server (Rust)
├── ostp             # Ospab Stealth Transport Protocol core implementation
├── b2b_connector    # Integration modules for B2B proxy clients
└── docs             # Comprehensive technical design documents
```

---

## Build Automation

The cross-compilation pipeline is fully automated using PowerShell.

```powershell
# Compile both the Go core and Flutter client in release mode
.\build.ps1 -BuildType release -PublishMode none

# Compile the project in debug mode
.\build.ps1 -BuildType debug -PublishMode none
```

All compiled binaries are stored in the `/builded` directory.

---

## Component Documentation

Additional technical documentation is available:
- [System Architecture](docs/ru/architecture.md)
- [Mobile Application Development](docs/ru/mobile_app.md)
- [Master Node Specification](docs/ru/master_node.md)
- [User Interface & Design tokens](docs/ru/design.md)
