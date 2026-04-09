-- Создание таблицы для API ключей
CREATE TABLE api_keys (
    id SERIAL PRIMARY KEY,
    key_id VARCHAR(32) UNIQUE NOT NULL,  -- Уникальный ID ключа
    api_key_hash VARCHAR(64) UNIQUE NOT NULL,  -- Хеш API ключа
    name VARCHAR(255) NOT NULL,  -- Название клиента/компании
    email VARCHAR(255),  -- Email клиента
    tier VARCHAR(20) DEFAULT 'starter',  -- Тариф: starter, business, enterprise
    balance_usd DECIMAL(10,2) DEFAULT 0.00,  -- Баланс
    traffic_limit_gb DECIMAL(10,2) DEFAULT 50.00,  -- Лимит трафика
    traffic_used_gb DECIMAL(10,2) DEFAULT 0.00,  -- Использовано трафика
    max_sessions INTEGER DEFAULT 5,  -- Максимальных сессий
    allowed_countries TEXT[],  -- Разрешенные страны
    is_active BOOLEAN DEFAULT true,  -- Активен ли ключ
    expires_at TIMESTAMP,  -- Срок действия
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP
);

-- Создание таблицы для сессий
CREATE TABLE api_sessions (
    id SERIAL PRIMARY KEY,
    api_key_id INTEGER REFERENCES api_keys(id),
    session_id VARCHAR(64) UNIQUE NOT NULL,
    client_ip INET,
    country_filter VARCHAR(20),
    connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    bytes_transferred BIGINT DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

-- Создание таблицы для статистики использования
CREATE TABLE usage_stats (
    id SERIAL PRIMARY KEY,
    api_key_id INTEGER REFERENCES api_keys(id),
    date DATE NOT NULL,
    bytes_transferred BIGINT DEFAULT 0,
    requests_count INTEGER DEFAULT 0,
    sessions_count INTEGER DEFAULT 0,
    countries_used TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для производительности
CREATE INDEX idx_api_keys_key_id ON api_keys(key_id);
CREATE INDEX idx_api_keys_tier ON api_keys(tier);
CREATE INDEX idx_api_keys_active ON api_keys(is_active);
CREATE INDEX idx_api_sessions_api_key ON api_sessions(api_key_id);
CREATE INDEX idx_api_sessions_active ON api_sessions(is_active);
CREATE INDEX idx_usage_stats_date ON usage_stats(date);
CREATE INDEX idx_usage_stats_api_key ON usage_stats(api_key_id);
