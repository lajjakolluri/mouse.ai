-- Update trial duration from 7 to 15 days
-- Remove credit card requirement

-- Update trigger function to use 15 days
CREATE OR REPLACE FUNCTION trigger_start_trial()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.anthropic_api_key_encrypted IS NOT NULL AND OLD.anthropic_api_key_encrypted IS NULL THEN
        NEW.trial_started_at = CURRENT_TIMESTAMP;
        NEW.trial_ends_at = CURRENT_TIMESTAMP + INTERVAL '15 days';  -- Changed from 7 to 15
        NEW.subscription_status = 'trial';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add savings tracking columns
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS total_requests INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_cost_without_optimization DECIMAL(10,6) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_cost_with_optimization DECIMAL(10,6) DEFAULT 0,
ADD COLUMN IF NOT EXISTS invoice_amount DECIMAL(10,6) DEFAULT 0,
ADD COLUMN IF NOT EXISTS invoice_generated_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS invoice_paid BOOLEAN DEFAULT FALSE;

-- Add detailed usage tracking
ALTER TABLE api_usage
ADD COLUMN IF NOT EXISTS timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Create invoice generation function
CREATE OR REPLACE FUNCTION calculate_invoice(user_id_param INTEGER)
RETURNS DECIMAL AS $$
DECLARE
    total_savings DECIMAL;
    invoice DECIMAL;
BEGIN
    -- Calculate total savings
    SELECT COALESCE(SUM(cost_saved), 0) INTO total_savings
    FROM api_usage
    WHERE user_id = user_id_param;
    
    -- Invoice is 50% of savings
    invoice := total_savings * 0.5;
    
    -- Update user record
    UPDATE users 
    SET invoice_amount = invoice,
        invoice_generated_at = CURRENT_TIMESTAMP
    WHERE id = user_id_param;
    
    RETURN invoice;
END;
$$ LANGUAGE plpgsql;

COMMIT;
