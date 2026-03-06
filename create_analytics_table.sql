CREATE TABLE IF NOT EXISTS api_usage (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(255) UNIQUE NOT NULL,
    customer_id VARCHAR(255),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    model_used VARCHAR(100),
    input_tokens INTEGER,
    output_tokens INTEGER,
    total_tokens INTEGER,
    original_cost DECIMAL(10, 6),
    optimized_cost DECIMAL(10, 6),
    cost_saved DECIMAL(10, 6),
    cache_hit BOOLEAN DEFAULT FALSE,
    latency_ms DECIMAL(10, 2),
    query_complexity INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customer_id ON api_usage(customer_id);
CREATE INDEX idx_timestamp ON api_usage(timestamp);
CREATE INDEX idx_model_used ON api_usage(model_used);
