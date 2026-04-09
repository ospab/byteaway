# ByteAway Security Principles

This project follows defense-in-depth and least-privilege principles.

## 1. Transport Security
- Use HTTPS/WSS for all production traffic.
- Disallow cleartext traffic in Android production config.
- Do not trust user-installed CA certificates in production.

## 2. Authentication and Secrets
- Require bearer authentication for protected API endpoints.
- Never log raw API keys, bearer tokens, or session tokens.
- Keep secrets in environment variables, never in source files.

## 3. Input and Request Hardening
- Apply strict request body limits to reduce abuse and memory pressure.
- Validate manifest/update metadata before installation.
- Reject unsafe or malformed update metadata.

## 4. Client Update Security
- Validate update source host and protocol.
- Enforce anti-rollback checks for app updates.
- Verify APK integrity (size and SHA-256) before install.

## 5. Response Hardening
- Send security headers on server responses:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Referrer-Policy: no-referrer`
  - `Permissions-Policy` with restrictive defaults
  - `Strict-Transport-Security`

## 6. Operational Security
- Keep dependencies updated and patch known vulnerabilities.
- Rotate API keys and credentials regularly.
- Use least-privilege DB and Redis accounts.
- Audit logs for abuse patterns and authentication failures.
