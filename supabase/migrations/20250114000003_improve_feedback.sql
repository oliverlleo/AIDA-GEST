BEGIN;

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

    -- Hardening Variables
    v_auth_state public.employee_auth_state%ROWTYPE;
    v_lock_minutes int;
BEGIN
    -- 1. Find workspace
    SELECT * INTO v_workspace_record FROM public.workspaces WHERE company_code = p_company_code;
    IF v_workspace_record.id IS NULL THEN
        PERFORM pg_sleep(0.3 + random() * 0.3);
        RAISE EXCEPTION 'Credenciais inválidas';
    END IF;

    -- 2. Find employee
    SELECT * INTO v_employee_record
    FROM public.employees e
    WHERE e.workspace_id = v_workspace_record.id
    AND e.username = p_username
    AND e.deleted_at IS NULL;

    IF v_employee_record.id IS NULL THEN
        PERFORM pg_sleep(0.3 + random() * 0.3);
        RAISE EXCEPTION 'Credenciais inválidas';
    END IF;

    -- 3. Lockout Check
    INSERT INTO public.employee_auth_state (employee_id) VALUES (v_employee_record.id)
    ON CONFLICT (employee_id) DO NOTHING;

    SELECT * INTO v_auth_state FROM public.employee_auth_state
    WHERE employee_id = v_employee_record.id FOR UPDATE;

    IF v_auth_state.reset_required THEN
            RAISE EXCEPTION 'Conta bloqueada. Solicite ao administrador.';
    END IF;

    IF v_auth_state.lock_until IS NOT NULL AND v_auth_state.lock_until > now() THEN
            RAISE EXCEPTION 'Muitas tentativas. Tente novamente mais tarde.';
    END IF;

    -- 4. Verify password
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN

        -- SUCCESS
        UPDATE public.employee_auth_state
        SET failed_attempts = 0, lock_until = NULL, lock_count = 0, reset_required = FALSE, updated_at = now()
        WHERE employee_id = v_employee_record.id;

        INSERT INTO public.employee_sessions (employee_id, expires_at)
        VALUES (v_employee_record.id, now() + interval '30 days')
        RETURNING public.employee_sessions.token INTO v_token;

        RETURN QUERY SELECT
            v_token,
            (to_jsonb(v_employee_record) || jsonb_build_object(
                'workspace_name', v_workspace_record.name,
                'company_code', v_workspace_record.company_code,
                'tracker_config', v_workspace_record.tracker_config
            )) as employee_json,
            v_employee_record.must_change_password;
    ELSE
        -- FAILURE
        v_auth_state.failed_attempts := v_auth_state.failed_attempts + 1;
        v_auth_state.lock_count := v_auth_state.lock_count + 1;
        v_lock_minutes := LEAST(10 * power(2, v_auth_state.lock_count - 1)::int, 1440);

        UPDATE public.employee_auth_state
        SET failed_attempts = v_auth_state.failed_attempts,
            lock_count = v_auth_state.lock_count,
            lock_until = now() + (v_lock_minutes || ' minutes')::interval,
            reset_required = (v_auth_state.failed_attempts >= 3),
            updated_at = now()
        WHERE employee_id = v_employee_record.id;

        PERFORM pg_sleep(0.3 + random() * 0.3);

        -- Custom Feedback based on attempts
        IF v_auth_state.failed_attempts >= 3 THEN
             RAISE EXCEPTION 'Conta bloqueada por excesso de tentativas. Solicite ao administrador.';
        ELSIF v_auth_state.failed_attempts = 2 THEN
             RAISE EXCEPTION 'Credenciais inválidas. Atenção: Última tentativa antes do bloqueio.';
        ELSE
             RAISE EXCEPTION 'Credenciais inválidas';
        END IF;
    END IF;
END;
$function$;

COMMIT;
