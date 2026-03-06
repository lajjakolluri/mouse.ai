-- Trial Schema for Monse.AI
ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_started_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_used BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_status VARCHAR(50) DEFAULT 'trial';
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_started_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_current_period_end TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_cancel_at_period_end BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS anthropic_api_key_encrypted TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS anthropic_api_key_added_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS anthropic_api_key_verified BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_reminder_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_ending_reminder_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_savings_usd DECIMAL(10, 2) DEFAULT 0;

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

DROP TRIGGER IF EXISTS trigger_start_trial ON users;
CREATE TRIGGER trigger_start_trial
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION start_trial_on_api_key();

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
