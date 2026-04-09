-- Free tier daily traffic quota: 1 GiB/day per client.
-- Used by /api/v1/vpn/config and /api/v1/vpn/traffic-report.

CREATE TABLE IF NOT EXISTS client_daily_traffic (
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    traffic_date DATE NOT NULL,
    bytes_used BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (client_id, traffic_date)
);

CREATE INDEX IF NOT EXISTS idx_client_daily_traffic_date
    ON client_daily_traffic(traffic_date);
