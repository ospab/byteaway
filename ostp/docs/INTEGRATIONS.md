# OSTP Integrations Guide

This guide explains how to use OSTP client proxy (`127.0.0.1:1088` by default) from desktop and mobile applications.

## 1. Proxy Type

OSTP client exposes a SOCKS5 proxy (no auth):
- host: `127.0.0.1`
- port: `1088`

Use SOCKS5 settings in applications. For command-line tools, prefer hostname-aware mode (`socks5h`) so DNS also goes through proxy.

## 2. Quick Validation

```bash
curl --proxy socks5h://127.0.0.1:1088 https://2ip.io
```

Expected: public IP of OSTP server egress host.

## 3. Windows Desktop

### Browser (Firefox)
1. Settings -> Network Settings -> Manual proxy configuration.
2. SOCKS Host: `127.0.0.1`, Port: `1088`.
3. SOCKS v5, enable proxy DNS over SOCKS.

### Browser (Chromium/Chrome/Edge)
Launch with SOCKS5:

```powershell
chrome.exe --proxy-server="socks5://127.0.0.1:1088"
```

### Git

```bash
git config --global http.proxy socks5h://127.0.0.1:1088
git config --global https.proxy socks5h://127.0.0.1:1088
```

## 4. Linux Desktop

### Shell tools

```bash
export ALL_PROXY=socks5h://127.0.0.1:1088
export HTTPS_PROXY=socks5h://127.0.0.1:1088
export HTTP_PROXY=socks5h://127.0.0.1:1088
```

### APT (when needed)
Create `/etc/apt/apt.conf.d/99proxy`:

```text
Acquire::http::Proxy "socks5h://127.0.0.1:1088";
Acquire::https::Proxy "socks5h://127.0.0.1:1088";
```

## 5. Android

Most apps do not support SOCKS5 directly. Use one of these:
- Local proxy-capable browser/app that supports SOCKS5 host/port.
- System-level tunnel app (VPN-style local forwarder) that can forward app traffic to SOCKS5 endpoint.

Typical setup values:
- SOCKS host: `127.0.0.1` (or device-local host where OSTP client runs)
- SOCKS port: `1088`

If OSTP client runs on another machine in LAN, use that machine's LAN IP and ensure firewall allows access.

## 6. App Integration Checklist

1. Start `ostp-server`.
2. Start `ostp-client` and ensure status is `Established`.
3. Configure app to SOCKS5 endpoint.
4. Validate external IP and basic HTTPS request.
5. Watch server TUI RX/TX and peer count.

## 7. Common Issues

- `Connection reset by peer` with `curl -x http://...`: wrong protocol type. Use SOCKS5 (`socks5h://`).
- No traffic in server UI: check client `server_addr` and `access_key`.
- App bypasses proxy: app may ignore system proxy; configure per-app SOCKS or use a forwarding tool.
