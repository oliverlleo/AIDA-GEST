
-- 1. Add Soft Delete Columns
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;

-- 2. Indexes for Optimization (Tickets)
CREATE INDEX IF NOT EXISTS idx_tickets_workspace_status ON public.tickets (workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_tickets_technician ON public.tickets (technician_id);
CREATE INDEX IF NOT EXISTS idx_tickets_deleted_at ON public.tickets (deleted_at);

-- 3. Update Employee Login RPC (Prevent login if deleted)
-- Drop first to allow return type change
DROP FUNCTION IF EXISTS public.employee_login(text, text, text);

CREATE OR REPLACE FUNCTION public.employee_login(
    p_company_code TEXT,
    p_username TEXT,
    p_password TEXT
) RETURNS TABLE (
    employee_id UUID,
    workspace_id UUID,
    workspace_name TEXT, -- Added
    company_code TEXT,   -- Added
    name TEXT,
    roles TEXT[],
    token TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_workspace_id UUID;
    v_workspace_name TEXT;
    v_company_code_found TEXT;
    v_employee_record RECORD;
BEGIN
    -- Find workspace by code (Use alias w to avoid ambiguity with output param 'name')
    SELECT w.id, w.name, w.company_code INTO v_workspace_id, v_workspace_name, v_company_code_found
    FROM public.workspaces w
    WHERE w.company_code = p_company_code;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Código da empresa inválido';
    END IF;

    -- Find employee (EXCLUDING DELETED)
    -- Using alias e
    SELECT * INTO v_employee_record
    FROM public.employees e
    WHERE e.workspace_id = v_workspace_id
    AND e.username = p_username
    AND e.deleted_at IS NULL;

    IF v_employee_record.id IS NULL THEN
        RAISE EXCEPTION 'Usuário inválido';
    END IF;

    -- Verify password
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN
        RETURN QUERY SELECT
            v_employee_record.id,
            v_employee_record.workspace_id,
            v_workspace_name,
            v_company_code_found,
            v_employee_record.name,
            v_employee_record.roles,
            'valid_session'::TEXT;
    ELSE
        RAISE EXCEPTION 'Senha incorreta';
    END IF;
END;
$$;

-- 4. Update Fetch Employees RPC (Exclude deleted)
DROP FUNCTION IF EXISTS public.get_employees_for_workspace(uuid);

CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(
    p_workspace_id UUID
) RETURNS TABLE (
    id UUID,
    workspace_id UUID,
    name TEXT,
    username TEXT,
    roles TEXT[],
    created_at TIMESTAMP WITH TIME ZONE,
    plain_password TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT e.id, e.workspace_id, e.name, e.username, e.roles, e.created_at, e.plain_password
    FROM public.employees e
    WHERE e.workspace_id = p_workspace_id
    AND e.deleted_at IS NULL
    ORDER BY e.created_at DESC;
END;
$$;
