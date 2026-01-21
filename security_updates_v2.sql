-- ==============================================================================
-- MIGRATION: SECURITY UPDATE V2
-- Eliminate plain_password + Implement must_change_password + Secure Sessions
-- ==============================================================================

-- 0. Enable pgcrypto for hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Create Employee Sessions Table
CREATE TABLE IF NOT EXISTS public.employee_sessions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- RLS for sessions (Implicit security via RPC, but good practice)
ALTER TABLE public.employee_sessions ENABLE ROW LEVEL SECURITY;

-- 2. Add must_change_password to employees
ALTER TABLE public.employees
ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT FALSE;

-- 3. Update create_employee (Remove plain_password, Set must_change_password)
DROP FUNCTION IF EXISTS create_employee(uuid, text, text, text, text[]);
CREATE OR REPLACE FUNCTION create_employee(
    p_workspace_id UUID,
    p_name TEXT,
    p_username TEXT,
    p_password TEXT,
    p_roles TEXT[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_id UUID;
BEGIN
    INSERT INTO public.employees (workspace_id, name, username, password_hash, roles, must_change_password)
    VALUES (
        p_workspace_id,
        p_name,
        p_username,
        crypt(p_password, gen_salt('bf')),
        p_roles,
        TRUE -- Always force password change on creation
    )
    RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$$;

-- 4. Update update_employee (Remove plain_password logic)
CREATE OR REPLACE FUNCTION update_employee(
    p_id UUID,
    p_name TEXT,
    p_username TEXT,
    p_password TEXT,
    p_roles TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE employees
    SET
        name = p_name,
        username = p_username,
        -- Update hash only if password is provided
        password_hash = CASE
            WHEN p_password IS NOT NULL AND p_password <> ''
            THEN crypt(p_password, gen_salt('bf'))
            ELSE password_hash
        END,
        -- If password changed, maybe force change again?
        -- Usually admin changing password means reset, so yes, let's force it if password is set.
        must_change_password = CASE
            WHEN p_password IS NOT NULL AND p_password <> '' THEN TRUE
            ELSE must_change_password
        END,
        roles = p_roles
    WHERE id = p_id;
END;
$$;

-- 5. Update employee_login (Generate Token, Check Session)
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
    token TEXT,
    must_change_password BOOLEAN
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_workspace_id UUID;
    v_employee_record RECORD;
    v_token TEXT;
BEGIN
    -- Find workspace by code
    SELECT id INTO v_workspace_id FROM public.workspaces WHERE company_code = p_company_code;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Código da empresa inválido';
    END IF;

    -- Find employee
    SELECT * INTO v_employee_record
    FROM public.employees e
    WHERE e.workspace_id = v_workspace_id
    AND e.username = p_username
    AND e.deleted_at IS NULL; -- Ensure deleted employees can't login

    IF v_employee_record.id IS NULL THEN
        RAISE EXCEPTION 'Usuário inválido';
    END IF;

    -- Verify password
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN

        -- Generate Token
        v_token := encode(gen_random_bytes(32), 'hex');

        -- Create Session (24h validity)
        INSERT INTO public.employee_sessions (employee_id, token, expires_at)
        VALUES (v_employee_record.id, v_token, timezone('utc'::text, now()) + interval '24 hours');

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

-- 6. Create reset_employee_password (Admin Only)
CREATE OR REPLACE FUNCTION reset_employee_password(
    p_employee_id UUID,
    p_new_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_owner_id UUID;
BEGIN
    -- 1. Validate Admin Permissions
    -- Check if the executing user (auth.uid()) is the owner of the workspace
    -- associated with the target employee.

    SELECT w.owner_id INTO v_owner_id
    FROM public.employees e
    JOIN public.workspaces w ON e.workspace_id = w.id
    WHERE e.id = p_employee_id;

    IF v_owner_id IS NULL OR v_owner_id <> auth.uid() THEN
        RAISE EXCEPTION 'Permissão negada. Apenas o administrador da empresa pode resetar senhas.';
    END IF;

    -- 2. Update Employee
    UPDATE public.employees
    SET
        password_hash = crypt(p_new_password, gen_salt('bf')),
        must_change_password = TRUE
    WHERE id = p_employee_id;

    -- 3. Revoke all active sessions
    UPDATE public.employee_sessions
    SET revoked_at = now()
    WHERE employee_id = p_employee_id AND revoked_at IS NULL;

END;
$$;

-- 7. Create employee_change_password (Self Service via Token)
CREATE OR REPLACE FUNCTION employee_change_password(
    p_token TEXT,
    p_old_password TEXT,
    p_new_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session RECORD;
    v_employee RECORD;
BEGIN
    -- 1. Validate Token
    SELECT * INTO v_session
    FROM public.employee_sessions
    WHERE token = p_token
      AND revoked_at IS NULL
      AND expires_at > now();

    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'Sessão inválida ou expirada. Faça login novamente.';
    END IF;

    -- 2. Update Session Activity
    UPDATE public.employee_sessions
    SET last_seen_at = now()
    WHERE id = v_session.id;

    -- 3. Get Employee
    SELECT * INTO v_employee
    FROM public.employees
    WHERE id = v_session.employee_id;

    -- 4. Verify Old Password
    IF v_employee.password_hash <> crypt(p_old_password, v_employee.password_hash) THEN
        RAISE EXCEPTION 'Senha atual incorreta.';
    END IF;

    -- 5. Update Password
    UPDATE public.employees
    SET
        password_hash = crypt(p_new_password, gen_salt('bf')),
        must_change_password = FALSE
    WHERE id = v_session.employee_id;

END;
$$;

-- 8. Final Cleanup: Drop plain_password
ALTER TABLE public.employees DROP COLUMN IF EXISTS plain_password;
