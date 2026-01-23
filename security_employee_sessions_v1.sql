-- ==============================================================================
-- MIGRATION: SECURITY EMPLOYEE SESSIONS V1
-- Secure Authentication & Token Validation
-- ==============================================================================

-- 0. Enable pgcrypto (Ensure it's active)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Ensure employee_sessions table matches specs
-- (It might already exist from previous step, but we reinforce structure)
CREATE TABLE IF NOT EXISTS public.employee_sessions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    token UUID NOT NULL DEFAULT gen_random_uuid(), -- Changed to UUID as per prompt recommendation, was TEXT before
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (now() + interval '30 days'),
    revoked_at TIMESTAMP WITH TIME ZONE,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Ensure indexes
CREATE INDEX IF NOT EXISTS idx_employee_sessions_token ON public.employee_sessions (token);
CREATE INDEX IF NOT EXISTS idx_employee_sessions_employee_id ON public.employee_sessions (employee_id);

-- Drop previous text-based column if it exists and isn't uuid (migration safety)
-- In a real prod env we would migrate data, but here we can just reset for safety/simplicity given the task scope
-- or alter the type.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'employee_sessions' AND column_name = 'token' AND data_type = 'text') THEN
        ALTER TABLE public.employee_sessions DROP COLUMN token;
        ALTER TABLE public.employee_sessions ADD COLUMN token UUID NOT NULL DEFAULT gen_random_uuid();
        CREATE INDEX IF NOT EXISTS idx_employee_sessions_token ON public.employee_sessions (token);
    END IF;
END $$;


-- 2. Helper: Validate Token & Get Employee (For RLS and RPCs)
CREATE OR REPLACE FUNCTION public.current_employee_from_token()
RETURNS TABLE (employee_id UUID, workspace_id UUID, role TEXT[])
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_token_str TEXT;
    v_token UUID;
BEGIN
    -- Try to get header
    v_token_str := current_setting('request.headers', true)::json->>'x-employee-token';

    IF v_token_str IS NULL THEN
        RETURN;
    END IF;

    -- Cast to UUID
    BEGIN
        v_token := v_token_str::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN;
    END;

    RETURN QUERY
    SELECT s.employee_id, e.workspace_id, e.roles
    FROM public.employee_sessions s
    JOIN public.employees e ON e.id = s.employee_id
    WHERE s.token = v_token
      AND s.revoked_at IS NULL
      AND s.expires_at > now();
END;
$$;


-- 3. Update employee_login (Return UUID token)
DROP FUNCTION IF EXISTS public.employee_login(text, text, text);
CREATE OR REPLACE FUNCTION public.employee_login(
    p_company_code TEXT,
    p_username TEXT,
    p_password TEXT
) RETURNS TABLE (
    employee_id UUID,
    workspace_id UUID,
    name TEXT,
    roles TEXT[],
    token UUID, -- UUID now
    must_change_password BOOLEAN
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_workspace_id UUID;
    v_employee_record RECORD;
    v_token UUID;
BEGIN
    -- Find workspace
    SELECT id INTO v_workspace_id FROM public.workspaces WHERE company_code = p_company_code;
    IF v_workspace_id IS NULL THEN RAISE EXCEPTION 'Código da empresa inválido'; END IF;

    -- Find employee
    SELECT * INTO v_employee_record
    FROM public.employees e
    WHERE e.workspace_id = v_workspace_id
    AND e.username = p_username
    AND e.deleted_at IS NULL;

    IF v_employee_record.id IS NULL THEN RAISE EXCEPTION 'Usuário inválido'; END IF;

    -- Verify password
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN

        -- Create Session
        INSERT INTO public.employee_sessions (employee_id, expires_at)
        VALUES (v_employee_record.id, now() + interval '30 days')
        RETURNING public.employee_sessions.token INTO v_token;

        RETURN QUERY SELECT
            v_employee_record.id,
            v_employee_record.workspace_id,
            v_employee_record.name,
            v_employee_record.roles,
            v_token,
            v_employee_record.must_change_password;
    ELSE
        RAISE EXCEPTION 'Senha incorreta';
    END IF;
END;
$$;


-- 4. Update employee_change_password (UUID token)
DROP FUNCTION IF EXISTS public.employee_change_password(text, text, text); -- Drop old signature
CREATE OR REPLACE FUNCTION employee_change_password(
    p_token UUID, -- UUID
    p_old_password TEXT,
    p_new_password TEXT
)
RETURNS TABLE (new_token UUID) -- Return new token
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_session RECORD;
    v_employee RECORD;
    v_new_token UUID;
BEGIN
    -- Validate Token
    SELECT * INTO v_session
    FROM public.employee_sessions
    WHERE token = p_token
      AND revoked_at IS NULL
      AND expires_at > now();

    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'Sessão inválida ou expirada.';
    END IF;

    -- Get Employee
    SELECT * INTO v_employee FROM public.employees WHERE id = v_session.employee_id;

    -- Verify Old Password
    IF v_employee.password_hash <> crypt(p_old_password, v_employee.password_hash) THEN
        RAISE EXCEPTION 'Senha atual incorreta.';
    END IF;

    -- Update Password
    UPDATE public.employees
    SET password_hash = crypt(p_new_password, gen_salt('bf')),
        must_change_password = FALSE
    WHERE id = v_session.employee_id;

    -- Revoke Old Session (Optional but recommended)
    UPDATE public.employee_sessions SET revoked_at = now() WHERE id = v_session.id;

    -- Create New Session
    INSERT INTO public.employee_sessions (employee_id, expires_at)
    VALUES (v_session.employee_id, now() + interval '30 days')
    RETURNING token INTO v_new_token;

    RETURN QUERY SELECT v_new_token;
END;
$$;


-- 5. Create validate_employee_session
CREATE OR REPLACE FUNCTION public.validate_employee_session(p_token UUID)
RETURNS TABLE (
    valid boolean,
    employee_id UUID,
    workspace_id UUID,
    roles TEXT[]
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_session RECORD;
BEGIN
    SELECT s.id, s.employee_id, e.workspace_id, e.roles
    INTO v_session
    FROM public.employee_sessions s
    JOIN public.employees e ON e.id = s.employee_id
    WHERE s.token = p_token
      AND s.revoked_at IS NULL
      AND s.expires_at > now();

    IF v_session.id IS NOT NULL THEN
        -- Update Activity
        UPDATE public.employee_sessions SET last_seen_at = now() WHERE id = v_session.id;

        RETURN QUERY SELECT true, v_session.employee_id, v_session.workspace_id, v_session.roles;
    ELSE
        RETURN QUERY SELECT false, null::uuid, null::uuid, null::text[];
    END IF;
END;
$$;


-- 6. Create employee_logout
CREATE OR REPLACE FUNCTION public.employee_logout(p_token UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    UPDATE public.employee_sessions
    SET revoked_at = now()
    WHERE token = p_token;
END;
$$;


-- 7. Secure RLS Helper Policy (Example for Tickets)
-- Drop existing permissive policy if it exists
DROP POLICY IF EXISTS "Acesso Total Tickets" ON public.tickets;

-- Create secure policy using token
CREATE POLICY "Tickets Access Policy" ON public.tickets
AS PERMISSIVE
FOR ALL
TO anon, authenticated
USING (
    -- Admin via Supabase Auth
    (auth.role() = 'authenticated' AND EXISTS (
        SELECT 1 FROM public.workspaces w WHERE w.id = tickets.workspace_id AND w.owner_id = auth.uid()
    ))
    OR
    -- Employee via Token (Secure)
    (workspace_id = (SELECT workspace_id FROM public.current_employee_from_token()))
);

-- Apply similar logic to Employees table (so they can list peers but restricted to workspace)
DROP POLICY IF EXISTS "Acesso Total Employees" ON public.employees; -- Assuming it existed
CREATE POLICY "Employees Access Policy" ON public.employees
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
    (auth.role() = 'authenticated' AND EXISTS (
        SELECT 1 FROM public.workspaces w WHERE w.id = employees.workspace_id AND w.owner_id = auth.uid()
    ))
    OR
    (workspace_id = (SELECT workspace_id FROM public.current_employee_from_token()))
);
