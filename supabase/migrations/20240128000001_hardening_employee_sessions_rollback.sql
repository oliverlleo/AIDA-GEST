
-- Rollback hardening of employee_sessions and table grants

-- 1. Restore employee_sessions (approximate original state: wide open)
ALTER TABLE public.employee_sessions DISABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE public.employee_sessions TO anon;
GRANT ALL ON TABLE public.employee_sessions TO authenticated;
GRANT ALL ON TABLE public.employee_sessions TO PUBLIC;

-- 2. Restore dangerous permissions (References/Trigger) - skipping Truncate for safety but restoring if strict rollback needed.
-- We will restore REFERENCES and TRIGGER as they are most likely to cause schematic breaks if missing.

DO $$
DECLARE
    t text;
BEGIN
    FOR t IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('GRANT REFERENCES, TRIGGER ON TABLE public.%I TO anon, authenticated', t);
        -- Optional: EXECUTE format('GRANT TRUNCATE ON TABLE public.%I TO anon, authenticated', t);
    END LOOP;
END $$;
