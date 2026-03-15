CREATE OR REPLACE FUNCTION public.reset_employee_password(
    p_employee_id uuid,
    p_new_password text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_workspace_id UUID;
BEGIN
    -- 1. Get employee workspace_id
    SELECT e.workspace_id INTO v_workspace_id
    FROM public.employees e
    WHERE e.id = p_employee_id;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Funcionário não encontrado.';
    END IF;

    -- 2. Validate Admin Permissions using our helper
    IF NOT public.can_manage_workspace(v_workspace_id) THEN
        RAISE EXCEPTION 'Permissão negada. Apenas o administrador da empresa pode resetar senhas.';
    END IF;

    -- 3. Update Employee
    UPDATE public.employees
    SET
        password_hash = crypt(p_new_password, gen_salt('bf')),
        must_change_password = TRUE
    WHERE id = p_employee_id;

    -- 4. Revoke all active sessions
    UPDATE public.employee_sessions
    SET revoked_at = now()
    WHERE employee_id = p_employee_id AND revoked_at IS NULL;

    -- 5. Clear Lockout
    UPDATE public.employee_auth_state
    SET failed_attempts = 0, lock_until = NULL, lock_count = 0, reset_required = FALSE, updated_at = now()
    WHERE employee_id = p_employee_id;
END;
$function$;
