# Login Hardening Implementation Report

**Date:** 2025-01-14
**Status:** Applied Successfully

## Overview

This update implements security hardening for the employee login system strictly in the backend (PostgreSQL). It enforces progressive lockouts for repeated failures and prevents account enumeration.

### Changes Applied

1.  **New Table:** `public.employee_auth_state` (Isolated)
    *   Tracks failed attempts, lock status, and forced reset requirements.
    *   **Permissions:** Restricted to `service_role` and `postgres` only. No access for `anon` or `authenticated`.

2.  **Function Patch:** `public.employee_login`
    *   **Authentication Logic:** Directly handles password verification logic (`IF/ELSE`) to ensure fail counters are incremented on *any* password mismatch.
    *   **Lockout Check:** Before attempting login, checks if the user is locked (time-based) or requires a reset.
    *   **Failure Handling:** Increments counters, calculates progressive lock (`10 * 2^(lock_count-1)`), and sleeps (anti-enumeration).
    *   **Success Handling:** Resets counters upon successful login.

3.  **Function Patch:** `public.reset_employee_password`
    *   **Wrapped Logic:** Preserves original password reset logic.
    *   **State Clear:** Clears any lockout/reset flags for the employee upon admin reset.

## Applied SQL (Migration)

**File:** `supabase/migrations/20250114000001_fix_login_logic.sql`

```sql
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
    -- Ensure state record exists
    INSERT INTO public.employee_auth_state (employee_id) VALUES (v_employee_record.id)
    ON CONFLICT (employee_id) DO NOTHING;

    -- Lock row for update
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

        -- SUCCESS: Reset Counters
        UPDATE public.employee_auth_state
        SET failed_attempts = 0, lock_until = NULL, lock_count = 0, reset_required = FALSE, updated_at = now()
        WHERE employee_id = v_employee_record.id;

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
        -- FAILURE: Update Hardening State
        v_auth_state.failed_attempts := v_auth_state.failed_attempts + 1;
        v_auth_state.lock_count := v_auth_state.lock_count + 1;

        -- Calculate lock time: 10 * 2^(lock_count-1) (capped at 1440 mins / 24h)
        v_lock_minutes := LEAST(10 * power(2, v_auth_state.lock_count - 1)::int, 1440);

        UPDATE public.employee_auth_state
        SET failed_attempts = v_auth_state.failed_attempts,
            lock_count = v_auth_state.lock_count,
            lock_until = now() + (v_lock_minutes || ' minutes')::interval,
            reset_required = (v_auth_state.failed_attempts >= 3),
            updated_at = now()
        WHERE employee_id = v_employee_record.id;

        -- Anti-enumeration sleep
        PERFORM pg_sleep(0.3 + random() * 0.3);
        RAISE EXCEPTION 'Credenciais inválidas';
    END IF;
END;
$function$;

COMMIT;
```

## Test Checklist (Manual)

To be performed by QA/Admin via Frontend or Curl:

- [ ] **Wrong Password (1x):** Should return "Credenciais inválidas" after ~300-600ms delay.
- [ ] **Wrong Password (2x):** Should return "Credenciais inválidas".
- [ ] **Wrong Password (3x):** Should return "Credenciais inválidas".
- [ ] **Attempt 4 (Correct Password):** Should return "Conta bloqueada. Solicite ao administrador." (due to reset_required=true on 3rd fail).
- [ ] **Admin Action:** Log in as Admin -> Employees -> Select User -> Reset Password.
- [ ] **User Retry:** Log in with new password -> Should succeed.
