-- Add owner_id and country to mobile_nodes
ALTER TABLE mobile_nodes ADD COLUMN IF NOT EXISTS owner_id UUID;
ALTER TABLE mobile_nodes ADD COLUMN IF NOT EXISTS country VARCHAR(2);

-- Create index for country-based lookup
CREATE INDEX IF NOT EXISTS idx_mobile_nodes_country ON mobile_nodes(country);
