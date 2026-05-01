# OSTP Windows Client

## Build on Windows

From repository root in PowerShell:

```powershell
./scripts/build_client_windows.ps1
```

Options:

```powershell
./scripts/build_client_windows.ps1 -Mode Debug
./scripts/build_client_windows.ps1 -Mode Release -Target x86_64-pc-windows-msvc
```

## Output

Default release output:
- `target/x86_64-pc-windows-msvc/release/ostp-client.exe`
- `target/x86_64-pc-windows-msvc/release/ostp-client.toml`

The script creates `ostp-client.toml` from `ostp-client.toml.example` only if the file does not exist yet. Existing config is preserved across rebuilds.

## Configure

Edit `ostp-client.toml`:

```toml
[ostp]
server_addr = "YOUR_SERVER_IP:8443"
local_bind_addr = "0.0.0.0:0"
access_key = "UUID_FROM_SERVER"
handshake_timeout_ms = 10000
io_timeout_ms = 2500

[local_proxy]
bind_addr = "127.0.0.1:1088"
connect_timeout_ms = 15000
```

## Run

TUI mode:

```powershell
./target/x86_64-pc-windows-msvc/release/ostp-client.exe
```

Background mode (no TUI):

```powershell
./target/x86_64-pc-windows-msvc/release/ostp-client.exe --no-tui
```

## Validate

Use SOCKS5 in applications via `127.0.0.1:1088`.

Quick check in WSL or curl that supports SOCKS5:

```bash
curl --proxy socks5h://127.0.0.1:1088 https://2ip.io
```
