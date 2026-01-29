
-- 1. Hardening employee_sessions

ALTER TABLE public.employee_sessions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.employee_sessions FROM PUBLIC;
REVOKE ALL ON TABLE public.employee_sessions FROM anon;
REVOKE ALL ON TABLE public.employee_sessions FROM authenticated;

GRANT ALL ON TABLE public.employee_sessions TO service_role;
GRANT ALL ON TABLE public.employee_sessions TO postgres;

-- 2. Revoke dangerous permissions on ALL public tables

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
        EXECUTE format('REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLE public.%I FROM anon, authenticated', t);
    END LOOP;
END $$;
