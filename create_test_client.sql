-- 1. Создаем тестового клиента (если еще нет)
INSERT INTO clients (id, email, balance_usd)
VALUES ('550e8400-e29b-41d4-a716-446655440000', 'test_b2b@example.com', 100.00)
ON CONFLICT (id) DO UPDATE SET balance_usd = 100.00;

-- 2. Создаем API ключ для этого клиента
-- key_hash = SHA256 от "test_key_123"
INSERT INTO api_keys (key_hash, client_id, rate_limit_req_sec)
VALUES ('9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', '550e8400-e29b-41d4-a716-446655440000', 10)
ON CONFLICT (key_hash) DO NOTHING;

SELECT 'Test client created! ID: 550e8400-e29b-41d4-a716-446655440000, API KEY: test_key_123' as result;
