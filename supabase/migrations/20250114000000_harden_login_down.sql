DROP TABLE IF EXISTS public.employee_auth_state;

CREATE OR REPLACE FUNCTION public.employee_login(p_company_code text, p_username text, p_password text)
 RETURNS TABLE(token uuid, employee_json jsonb, must_change_password boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
DECLARE
    v_workspace_id UUID;
    v_employee_record RECORD;
    v_workspace_record RECORD;
    v_token UUID;
BEGIN
    -- Find workspace
    SELECT * INTO v_workspace_record FROM public.workspaces WHERE company_code = p_company_code;
    IF v_workspace_record.id IS NULL THEN RAISE EXCEPTION 'Código da empresa inválido'; END IF;

    -- Find employee
    SELECT * INTO v_employee_record
    FROM public.employees e
    WHERE e.workspace_id = v_workspace_record.id
    AND e.username = p_username
    AND e.deleted_at IS NULL;

    IF v_employee_record.id IS NULL THEN RAISE EXCEPTION 'Usuário inválido'; END IF;

    -- Verify password
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN

        -- Create Session
        INSERT INTO public.employee_sessions (employee_id, expires_at)
        VALUES (v_employee_record.id, now() + interval '30 days')
        RETURNING public.employee_sessions.token INTO v_token;

        -- Return Data
        RETURN QUERY SELECT
            v_token,
            (to_jsonb(v_employee_record) || jsonb_build_object(
                'workspace_name', v_workspace_record.name,
                'company_code', v_workspace_record.company_code,
                'tracker_config', v_workspace_record.tracker_config
            )) as employee_json,
            v_employee_record.must_change_password;
    ELSE
        RAISE EXCEPTION 'Senha incorreta';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reset_employee_password(p_employee_id uuid, p_new_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$;
