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
