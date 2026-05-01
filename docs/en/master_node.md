# Master Node and Proxy Infrastructure

The Master Node is the central hub and traffic coordinator of the ByteAway network. It provides authentication, usage accounting, load balancing for B2B clients, and orchestration of the distributed mobile node network.

## Architecture and Core Technologies

The backend is built in **Rust** using the **Tokio** asynchronous runtime and the **Axum** web framework. The system uses **PostgreSQL** for persistent data storage and **Redis** for caching and high-performance communication.

---

## Core Subsystems

### 1. REST API (`/api/v1`)
Facilitates communications with mobile applications, B2B clients, and admin dashboards:
- **Authentication**: Implements token-based security. Validates the status of accounts and their accessibility within the network.
- **Proxy Management**: Generates configurations for VPN connections and retrieves real-time usage and speed limits.
- **Billing**: Manages top-ups, calculates data costs, and records transaction histories.

### 2. Multiplexed Tunnels
Mobile nodes connect to the Master Node via dedicated ingress handlers. The system supports multiple transport protocols:
- **QUIC**: The primary UDP-based protocol. Delivers high speeds and retains robustness across cellular-to-Wi-Fi network handovers.
- **WebSocket (WS)**: The fallback protocol. Bypasses strict network firewalls that only permit standard HTTP/HTTPS traffic.
- **Hysteria2**: An alternative UDP-based transport protocol that leverages aggressive congestion control to maximize bandwidth across unstable links.

The **Yamux** multiplexer sits on top of these raw physical connections. This setup allows thousands of independent network sessions to run concurrently inside a single established link.

### 3. SOCKS5/HTTP Gateway
A proxy server that intercepts incoming requests from B2B clients and routes them to registered mobile devices:
- Upon receiving a new TCP connection, the gateway queries the registry for an available mobile node.
- The request is encapsulated within a yamux channel and sent to the selected mobile node.
- The mobile node performs the network request on behalf of the device and returns the response through the Master Node to the B2B client.

### 4. Billing Engine
Responsible for measuring bandwidth consumption and executing credit deductions:
- All data regarding relayed traffic (in bytes) is initially collected in memory and cached in Redis.
- Every 60 seconds, a background worker flushes this usage data from Redis to PostgreSQL.
- Based on the data volume processed, the B2B client's account balance is reduced according to active pricing models (defaulting to a fixed price per GB).

---

## State Management (Registry)

To track available nodes efficiently, the system utilizes a Redis-backed registry (`RedisNodeRegistry`):
- When a mobile node initiates a connection, it registers its unique identifier and metrics (country, region, bandwidth capacity).
- Registry records include a Time-To-Live (TTL) and are automatically pruned if the mobile node fails to submit periodic heartbeat pings.
- The load balancer selects nodes from the pool based on bandwidth availability and the client's geographic routing preferences.
