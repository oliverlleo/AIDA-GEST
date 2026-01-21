
ALTER TABLE employees ADD COLUMN IF NOT EXISTS plain_password TEXT;
-- Update existing records to have 'hidden' if null, or we can't recover them.
-- User wants to see the password.
-- Going forward, we should store it.
-- For existing, we can't recover.
