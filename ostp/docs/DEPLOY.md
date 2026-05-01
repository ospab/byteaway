# OSTP Deployment Guide (Linux x86_64)

## 1. Build

From repository root:

```bash
./scripts/deploy_ostp.sh
```

Default behavior:
- mode: `production`
- target: `x86_64-unknown-linux-gnu`
- packages: `ostp-client`, `ostp-server`

Other examples:

```bash
./scripts/deploy_ostp.sh debug
./scripts/deploy_ostp.sh production client
./scripts/deploy_ostp.sh --mode debug --part server
./scripts/deploy_ostp.sh --part all
```

## 2. Build outputs

Production binaries:
- `target/x86_64-unknown-linux-gnu/release/ostp-client`
- `target/x86_64-unknown-linux-gnu/release/ostp-server`

Debug binaries:
- `target/x86_64-unknown-linux-gnu/debug/ostp-client`
- `target/x86_64-unknown-linux-gnu/debug/ostp-server`

## 3. Client config (near binary)

The deployment script copies config template near the client binary:
- `target/x86_64-unknown-linux-gnu/release/ostp-client.toml`
- `target/x86_64-unknown-linux-gnu/debug/ostp-client.toml`

Config format:

```toml
[ostp]
server_addr = "127.0.0.1:8443"
local_bind_addr = "0.0.0.0:0"
access_key = "replace-with-server-key"
handshake_timeout_ms = 3000
io_timeout_ms = 300

[local_proxy]
bind_addr = "127.0.0.1:1088"
connect_timeout_ms = 8000
```

Notes:
- `server_addr` must point to your running OSTP server UDP socket.
- `access_key` must exist in server key file.

At runtime, `ostp-client` reads `ostp-client.toml` from the same directory as the executable.
If the file is missing, client creates it with default values.

## 4. Server config (near binary)

The deployment script copies server config template near the server binary:
- `target/x86_64-unknown-linux-gnu/release/ostp-server.toml`
- `target/x86_64-unknown-linux-gnu/debug/ostp-server.toml`

Config format:

```toml
bind_addr = "0.0.0.0:8443"
stream_id = 1
max_padding = 256
access_keys_file = "ostp-server-keys.txt"
max_datagram_size = 2048
peer_idle_timeout_secs = 120
```

At runtime, `ostp-server` reads `ostp-server.toml` from the same directory as the executable.
If the file is missing, server creates it with default values.

Server access keys are stored in the file from `access_keys_file` (default: `ostp-server-keys.txt`) near the binary.
If the key file does not exist, server creates it with one UUID key.

To authorize a client:
- open server TUI and press `N` to generate a new access key
- copy generated key from TUI logs
- put that key into client `ostp.access_key`

## 5. Local proxy in client

`ostp-client` starts a local SOCKS5 proxy (no-auth) from config:
- default bind: `127.0.0.1:1088`
- command support: `CONNECT`

Use it from applications as SOCKS5 endpoint.

## 6. Capabilities

When available, deploy script applies:
- `cap_net_admin,cap_net_raw+ep` to client binary

This allows tunnel-related networking operations without full root execution.

## 7. TUI controls

Inside `ostp-client` TUI:
- `Space`: start/stop tunnel flow
- `Tab`: switch obfuscation profile
- `K`: open config editor (server addr + access key)
- `B`: detach TUI and keep client running in background
- `Up/Down`: scroll logs
- `Esc` or `Q`: graceful exit

In key editor:
- `Tab`: switch input field
- `Enter`: save to `ostp-client.toml` and auto-reload runtime config
- `Esc`: cancel without saving

Inside `ostp-server` TUI:
- `N`: create new client access key (UUID)
- `Q` or `Esc`: shutdown server

Server TUI shows:
- connected clients count
- RX/TX speed (B/s)
- per-IP totals (ports are aggregated under same source IP)
- unauthorized probe counter

Headless launch (no TUI):
- `./ostp-server --no-tui`
- `./ostp-client --no-tui`

Data path behavior:
- SOCKS5 `CONNECT` traffic from client is relayed through OSTP to server.
- Server performs outbound TCP connect and egress, so external services should see server IP.

## 8. Troubleshooting

- `Missing dependency: cargo/rustup/pkg-config`: install Rust toolchain and pkg-config.
- `Missing package: libssl-dev`: install OpenSSL development headers.
- `Optional dependency not found: protoc/cmake`: warning only, build continues unless a crate actually needs them.
- `Unauthorized packet ...`: client `ostp.access_key` is missing or mismatched with server keys file.

## 9. Running server and client

Run server:

```bash
cd target/x86_64-unknown-linux-gnu/release
./ostp-server
```

Run client:

```bash
cd target/x86_64-unknown-linux-gnu/release
./ostp-client
```
