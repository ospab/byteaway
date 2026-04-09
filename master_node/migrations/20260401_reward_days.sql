-- Reward system for B2C: every 200 MiB shared = 1 day of unlimited VPN speed.
-- Countdown starts when VPN config is first requested with pending reward days.

ALTER TABLE clients
ADD COLUMN IF NOT EXISTS reward_shared_bytes_remainder BIGINT NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS reward_pending_days INT NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS reward_unlimited_until TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS reward_first_activated_at TIMESTAMPTZ;
