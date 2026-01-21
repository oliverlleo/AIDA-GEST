
-- Fix ambiguous column reference in employee_login
CREATE OR REPLACE FUNCTION public.employee_login(
    p_company_code TEXT,
    p_username TEXT,
    p_password TEXT
) RETURNS TABLE (
    employee_id UUID,
    workspace_id UUID, -- This name conflicted with table column
    name TEXT,
    roles TEXT[],
    token TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_workspace_id UUID;
    v_employee_record RECORD;
BEGIN
    -- Find workspace by code
    SELECT id INTO v_workspace_id FROM public.workspaces WHERE company_code = p_company_code;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Código da empresa inválido';
    END IF;

    -- Find employee
    -- FIXED: Qualified 'workspace_id' with table alias 'e'
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
            'valid_session'::TEXT;
    ELSE
        RAISE EXCEPTION 'Senha incorreta';
    END IF;
END;
$$;
