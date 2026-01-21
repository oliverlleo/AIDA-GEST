
-- Update employee_login to return tracker_config
DROP FUNCTION IF EXISTS public.employee_login(TEXT, TEXT, TEXT);

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
    company_code TEXT,
    tracker_config JSONB -- NEW
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_workspace_id UUID;
    v_workspace_name TEXT;
    v_tracker_config JSONB;
    v_employee_record RECORD;
BEGIN
    -- Find workspace
    SELECT id, name, tracker_config INTO v_workspace_id, v_workspace_name, v_tracker_config
    FROM public.workspaces
    WHERE company_code = p_company_code;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Código da empresa inválido';
    END IF;

    -- Find employee
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
            v_employee_record.name,
            v_employee_record.roles,
            'valid_session'::TEXT,
            v_workspace_name,
            p_company_code,
            v_tracker_config; -- Return config
    ELSE
        RAISE EXCEPTION 'Senha incorreta';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.employee_login(TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.employee_login(TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_login(TEXT, TEXT, TEXT) TO service_role;
