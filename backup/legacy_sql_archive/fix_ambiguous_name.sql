
-- Function: Employee Login Extended (Returns workspace name and code)
-- FIXED: Ambiguous "name" column reference by using aliases
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
    workspace_name TEXT,
    company_code TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_workspace_id UUID;
    v_workspace_name TEXT;
    v_employee_record RECORD;
BEGIN
    -- Find workspace by code
    -- Used alias 'w' to resolve ambiguity with output param 'name'
    SELECT w.id, w.name INTO v_workspace_id, v_workspace_name
    FROM public.workspaces w
    WHERE w.company_code = p_company_code;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Código da empresa inválido';
    END IF;

    -- Find employee
    SELECT * INTO v_employee_record
    FROM public.employees e
    WHERE e.workspace_id = v_workspace_id
    AND e.username = p_username;

    IF v_employee_record.id IS NULL THEN
        RAISE EXCEPTION 'Usuário inválido';
    END IF;

    -- Verify password
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN
        RETURN QUERY SELECT
            v_employee_record.id,
            v_employee_record.workspace_id,
            v_employee_record.name,
            v_employee_record.roles,
            'valid_session'::TEXT,
            v_workspace_name,
            p_company_code;
    ELSE
        RAISE EXCEPTION 'Senha incorreta';
    END IF;
END;
$$;
