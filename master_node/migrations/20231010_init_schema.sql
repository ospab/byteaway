-- Таблица B2B клиентов
CREATE TABLE IF NOT EXISTS clients (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    balance_usd DECIMAL(15, 6) DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Таблица API ключей
CREATE TABLE IF NOT EXISTS api_keys (
    key_hash VARCHAR(255) PRIMARY KEY,
    client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
    rate_limit_req_sec INT DEFAULT 10,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Таблица мобильных нод (пожизненная статистика)
CREATE TABLE IF NOT EXISTS mobile_nodes (
    id UUID PRIMARY KEY,
    device_id VARCHAR(255) UNIQUE NOT NULL,
    total_gb_provided DECIMAL(15, 6) DEFAULT 0.0,
    registered_at TIMESTAMPTZ DEFAULT NOW()
);

-- Агрегированная статистика использования
CREATE TABLE IF NOT EXISTS traffic_history (
    id BIGSERIAL PRIMARY KEY,
    client_id UUID REFERENCES clients(id),
    node_id UUID REFERENCES mobile_nodes(id),
    bytes_used BIGINT NOT NULL,
    billed_usd DECIMAL(15, 6) NOT NULL,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ
);

-- VPN Sessions table for tracking active and historical VPN connections
CREATE TABLE IF NOT EXISTS vpn_sessions (
    id BIGSERIAL PRIMARY KEY,
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    assigned_ip INET NOT NULL,
    vpn_gateway_id VARCHAR(64) DEFAULT 'default',
    bytes_upload BIGINT DEFAULT 0,
    bytes_download BIGINT DEFAULT 0,
    billed_usd DECIMAL(15, 6) DEFAULT 0.0,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE
);

-- Index for fast lookup of active sessions by client
CREATE INDEX IF NOT EXISTS idx_vpn_sessions_client_active 
    ON vpn_sessions(client_id, is_active) WHERE is_active = TRUE;

-- Index for billing calculations
CREATE INDEX IF NOT EXISTS idx_vpn_sessions_ended_at 
    ON vpn_sessions(ended_at) WHERE ended_at IS NOT NULL;

-- Index for gateway load balancing
CREATE INDEX IF NOT EXISTS idx_vpn_sessions_gateway 
    ON vpn_sessions(vpn_gateway_id, is_active);

-- VPN Gateways registry for multi-instance scaling
CREATE TABLE IF NOT EXISTS vpn_gateways (
    id VARCHAR(64) PRIMARY KEY,
    public_host VARCHAR(255) NOT NULL,
    public_port INT NOT NULL DEFAULT 5443,
    region VARCHAR(64),
    max_clients INT DEFAULT 1000,
    current_clients INT DEFAULT 0,
    is_healthy BOOLEAN DEFAULT TRUE,
    last_heartbeat TIMESTAMPTZ DEFAULT NOW(),
    reality_public_key VARCHAR(255),
    reality_short_id VARCHAR(32)
);
