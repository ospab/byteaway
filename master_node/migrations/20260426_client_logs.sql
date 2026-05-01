-- Migration to add client logs table for B2B error reporting
CREATE TABLE IF NOT EXISTS client_logs (
    id SERIAL PRIMARY KEY,
    client_id UUID NOT NULL REFERENCES clients(id),
    level VARCHAR(10) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_client_logs_client_id ON client_logs(client_id);
CREATE INDEX idx_client_logs_created_at ON client_logs(created_at);
