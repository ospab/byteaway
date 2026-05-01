-- Таблица устройств с HWID для защиты от клонов
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    hwid VARCHAR(255) UNIQUE NOT NULL,
    vless_uuid VARCHAR(36) UNIQUE NOT NULL DEFAULT gen_random_uuid()::text,
    device_name VARCHAR(255),
    os_type VARCHAR(50),
    os_version VARCHAR(50),
    app_version VARCHAR(50),
    first_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    is_blocked BOOLEAN DEFAULT FALSE
);

-- Индекс для быстрого поиска по HWID
CREATE INDEX IF NOT EXISTS idx_devices_hwid ON devices(hwid);

-- Индекс для поиска устройств клиента
CREATE INDEX IF NOT EXISTS idx_devices_client ON devices(client_id);

-- Индекс для поиска активных устройств
CREATE INDEX IF NOT EXISTS idx_devices_active ON devices(client_id, is_active) WHERE is_active = TRUE;

-- Уникальный индекс для предотвращения дубликатов HWID у одного клиента
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_client_hwid ON devices(client_id, hwid);

-- Индекс для поиска по vless_uuid
CREATE INDEX IF NOT EXISTS idx_devices_vless_uuid ON devices(vless_uuid);
