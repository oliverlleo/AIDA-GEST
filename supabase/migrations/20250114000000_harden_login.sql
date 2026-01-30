BEGIN;

-- 1. Create Table
CREATE TABLE IF NOT EXISTS public.employee_auth_state (
    employee_id uuid PRIMARY KEY REFERENCES public.employees(id) ON DELETE CASCADE,
    failed_attempts int NOT NULL DEFAULT 0,
    lock_until timestamptz NULL,
    lock_count int NOT NULL DEFAULT 0,
    reset_required boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Security
ALTER TABLE public.employee_auth_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.employee_auth_state FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.employee_auth_state FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.employee_auth_state FROM authenticated;

GRANT ALL PRIVILEGES ON TABLE public.employee_auth_state TO service_role;
GRANT ALL PRIVILEGES ON TABLE public.employee_auth_state TO postgres;

-- 3. Patch employee_login
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
    -- We wrap the original logic to intercept errors and inject hardening checks
    BEGIN
        -- === ORIGINAL LOGIC START (Lookup) ===
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
        -- === ORIGINAL LOGIC END (Lookup) ===

        -- === HARDENING INJECTION (Lockout Check) ===
        -- Ensure state record exists
        INSERT INTO public.employee_auth_state (employee_id) VALUES (v_employee_record.id)
        ON CONFLICT (employee_id) DO NOTHING;

        -- Lock row for update to prevent race conditions
        SELECT * INTO v_auth_state FROM public.employee_auth_state
        WHERE employee_id = v_employee_record.id FOR UPDATE;

        IF v_auth_state.reset_required THEN
             RAISE EXCEPTION 'Conta bloqueada. Solicite ao administrador.';
        END IF;

        IF v_auth_state.lock_until IS NOT NULL AND v_auth_state.lock_until > now() THEN
             RAISE EXCEPTION 'Muitas tentativas. Tente novamente mais tarde.';
        END IF;
        -- === END HARDENING INJECTION ===

        -- === ORIGINAL LOGIC START (Password & Session) ===
        -- Verify password
        IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN

            -- === HARDENING INJECTION (Success Reset) ===
            UPDATE public.employee_auth_state
            SET failed_attempts = 0, lock_until = NULL, lock_count = 0, reset_required = FALSE, updated_at = now()
            WHERE employee_id = v_employee_record.id;
            -- === END HARDENING INJECTION ===

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
        -- === ORIGINAL LOGIC END ===

    EXCEPTION
        WHEN OTHERS THEN
            -- Intercept specific auth errors to enforce generic messages and lockout
            IF SQLERRM = 'Código da empresa inválido' OR SQLERRM = 'Usuário inválido' THEN
                -- Anti-enumeration sleep
                PERFORM pg_sleep(0.3 + random() * 0.3);
                RAISE EXCEPTION 'Credenciais inválidas';

            ELSIF SQLERRM = 'Senha incorreta' THEN
                -- Lockout Logic
                -- Increment counters
                v_auth_state.failed_attempts := v_auth_state.failed_attempts + 1;
                v_auth_state.lock_count := v_auth_state.lock_count + 1;

                -- Calculate lock time: 10 * 2^lock_count (capped at 1440 mins / 24h)
                -- Using power() and casting to int
                -- Using (lock_count - 1) because count starts at 1 (after increment), so 2^(1-1) = 1 -> 10 mins.
                v_lock_minutes := LEAST(10 * power(2, v_auth_state.lock_count - 1)::int, 1440);

                UPDATE public.employee_auth_state
                SET failed_attempts = v_auth_state.failed_attempts, -- already incremented in variable
                    lock_count = v_auth_state.lock_count,
                    lock_until = now() + (v_lock_minutes || ' minutes')::interval,
                    reset_required = (v_auth_state.failed_attempts >= 3),
                    updated_at = now()
                WHERE employee_id = v_employee_record.id;

                -- Anti-enumeration sleep
                PERFORM pg_sleep(0.3 + random() * 0.3);
                RAISE EXCEPTION 'Credenciais inválidas';
            ELSE
                -- Re-raise other unexpected errors (e.g. DB errors)
                RAISE;
            END IF;
    END;
END;
$function$;

-- 4. Patch reset_employee_password
CREATE OR REPLACE FUNCTION public.reset_employee_password(p_employee_id uuid, p_new_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_owner_id UUID;
BEGIN
    -- === ORIGINAL LOGIC START ===
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
    -- === ORIGINAL LOGIC END ===

    -- === HARDENING INJECTION (Clear Lockout) ===
    UPDATE public.employee_auth_state
    SET failed_attempts = 0, lock_until = NULL, lock_count = 0, reset_required = FALSE, updated_at = now()
    WHERE employee_id = p_employee_id;
    -- === END HARDENING INJECTION ===

END;
$function$;

COMMIT;
