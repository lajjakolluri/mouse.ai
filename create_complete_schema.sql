-- Complete Monse.AI Database Schema

-- Drop existing if recreating
DROP TABLE IF EXISTS api_usage CASCADE;
DROP TABLE IF EXISTS user_sessions CASCADE;
DROP TABLE IF EXISTS user_api_keys CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    company_name VARCHAR(255),
    full_name VARCHAR(255),
    
    -- Monse.AI API key
    primary_api_key VARCHAR(255) UNIQUE NOT NULL,
    
    -- Plan & limits
    plan VARCHAR(50) DEFAULT 'trial',
    monthly_request_limit INTEGER DEFAULT 999999,
    current_month_requests INTEGER DEFAULT 0,
    
    -- Trial tracking
    trial_started_at TIMESTAMP,
    trial_ends_at TIMESTAMP,
    trial_used BOOLEAN DEFAULT FALSE,
    trial_reminder_sent BOOLEAN DEFAULT FALSE,
    trial_ending_reminder_sent BOOLEAN DEFAULT FALSE,
    
    -- Subscription
    subscription_status VARCHAR(50) DEFAULT 'pending',
    subscription_started_at TIMESTAMP,
    subscription_current_period_end TIMESTAMP,
    subscription_cancel_at_period_end BOOLEAN DEFAULT FALSE,
    
    -- Anthropic API key (encrypted)
    anthropic_api_key_encrypted TEXT,
    anthropic_api_key_added_at TIMESTAMP,
    anthropic_api_key_verified BOOLEAN DEFAULT FALSE,
    
    -- Savings tracking
    total_savings_usd DECIMAL(10, 2) DEFAULT 0,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    is_admin BOOLEAN DEFAULT FALSE,
    email_verified BOOLEAN DEFAULT TRUE,
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    
    -- Billing
    stripe_customer_id VARCHAR(255),
    stripe_subscription_id VARCHAR(255)
);

-- API usage tracking
CREATE TABLE api_usage (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    request_id VARCHAR(255),
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

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_api_key ON users(primary_api_key);
CREATE INDEX idx_users_stripe ON users(stripe_customer_id);
CREATE INDEX idx_api_usage_user ON api_usage(user_id);
CREATE INDEX idx_api_usage_timestamp ON api_usage(timestamp);

-- Function to start trial when API key is added
CREATE OR REPLACE FUNCTION start_trial_on_api_key()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.anthropic_api_key_encrypted IS NOT NULL 
       AND OLD.anthropic_api_key_encrypted IS NULL 
       AND NEW.trial_started_at IS NULL THEN
        NEW.trial_started_at := CURRENT_TIMESTAMP;
        NEW.trial_ends_at := CURRENT_TIMESTAMP + INTERVAL '7 days';
        NEW.subscription_status := 'trial';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger
CREATE TRIGGER trigger_start_trial
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION start_trial_on_api_key();

-- Function to check platform access
CREATE OR REPLACE FUNCTION can_use_platform(p_user_id INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    v_user RECORD;
BEGIN
    SELECT * INTO v_user FROM users WHERE id = p_user_id;
    
    IF v_user.is_admin THEN
        RETURN TRUE;
    END IF;
    
    IF v_user.anthropic_api_key_encrypted IS NULL THEN
        RETURN FALSE;
    END IF;
    
    IF v_user.subscription_status = 'trial' 
       AND v_user.trial_ends_at > CURRENT_TIMESTAMP THEN
        RETURN TRUE;
    END IF;
    
    IF v_user.subscription_status = 'active' 
       AND v_user.subscription_current_period_end > CURRENT_TIMESTAMP THEN
        RETURN TRUE;
    END IF;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Create test accounts
INSERT INTO users (
    email, password_hash, company_name, full_name,
    primary_api_key, plan, subscription_status, is_admin
) VALUES (
    'admin@monse.ai',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5UpRG.kU6Gmga',
    'Monse.AI', 'Admin User',
    'tok_admin_' || md5(random()::text),
    'enterprise', 'active', TRUE
);

INSERT INTO users (
    email, password_hash, company_name, full_name,
    primary_api_key, plan, subscription_status,
    trial_started_at, trial_ends_at
) VALUES (
    'trial@example.com',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5UpRG.kU6Gmga',
    'Trial Company', 'Trial User',
    'tok_trial_' || md5(random()::text),
    'trial', 'trial',
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '7 days'
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin;
