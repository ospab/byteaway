CREATE TABLE IF NOT EXISTS business_accounts (
    id UUID PRIMARY KEY,
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    company_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS business_sessions (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES business_accounts(id) ON DELETE CASCADE,
    session_hash VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_business_accounts_client_id
    ON business_accounts(client_id);

CREATE INDEX IF NOT EXISTS idx_business_sessions_account_id
    ON business_sessions(account_id);

CREATE INDEX IF NOT EXISTS idx_business_sessions_expires_at
    ON business_sessions(expires_at)
    WHERE revoked_at IS NULL;