# OSTP

OSTP workspace includes:
- `ostp-core`: protocol core (state machine, framing, crypto wrappers)
- `ostp-client`: terminal client with TUI and local SOCKS5 proxy (config near binary)
- `ostp-server`: UDP server runtime with per-peer sessions, server TUI, and key-based client provisioning
- `ostp-obfuscator`: traffic shaping profiles

Deployment and run instructions are in [docs/DEPLOY.md](docs/DEPLOY.md).
Application integration examples are in [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).
Windows client build/run guide is in [docs/WINDOWS_CLIENT.md](docs/WINDOWS_CLIENT.md).
