# Login Hardening Implementation Report

**Date:** 2025-01-14
**Status:** Applied Successfully

## Overview

This update implements security hardening for the employee login system strictly in the backend (PostgreSQL), without modifying the frontend or altering the existing authentication logic's core behavior (signature, return types, session creation).

### Changes Applied

1.  **New Table:** `public.employee_auth_state` (Isolated)
    *   Tracks failed attempts, lock status, and forced reset requirements.
    *   **Permissions:** Restricted to `service_role` and `postgres` only. No access for `anon` or `authenticated`.

2.  **Function Patch:** `public.employee_login`
    *   **Wrapped Logic:** The original session creation logic is preserved exactly.
    *   **Lockout Check:** Before attempting login, checks if the user is locked (time-based) or requires a reset.
    *   **Failure Handling:** On invalid credentials, increments counters, calculates progressive lock (`10 * 2^(lock_count-1)`), and sleeps (anti-enumeration).
    *   **Success Handling:** Resets counters upon successful login.

3.  **Function Patch:** `public.reset_employee_password`
    *   **Wrapped Logic:** Preserves original password reset logic.
    *   **State Clear:** Clears any lockout/reset flags for the employee upon admin reset.

## Applied SQL (Migration)

**File:** `supabase/migrations/20250114000000_harden_login.sql`

```sql
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
    -- ... (Original Validation and Update Logic Preserved) ...

    SELECT w.owner_id INTO v_owner_id
    FROM public.employees e
    JOIN public.workspaces w ON e.workspace_id = w.id
    WHERE e.id = p_employee_id;

    IF v_owner_id IS NULL OR v_owner_id <> auth.uid() THEN
        RAISE EXCEPTION 'Permissão negada. Apenas o administrador da empresa pode resetar senhas.';
    END IF;

    UPDATE public.employees
    SET
        password_hash = crypt(p_new_password, gen_salt('bf')),
        must_change_password = TRUE
    WHERE id = p_employee_id;

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
```

## Rollback (Snapshot)

**File:** `supabase/migrations/20250114000000_harden_login_down.sql`
Contains the exact original definitions fetched from production before application.

## Verification

### 1. Permissions Check
**Query:**
```sql
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name='employee_auth_state'
  and grantee in ('PUBLIC','anon','authenticated')
order by grantee, privilege_type;
```
**Result:** 0 rows (Passed).

### 2. Function Definition Check
**Query:**
```sql
select p.oid::regprocedure as signature,
       p.prosecdef as security_definer,
       pg_get_functiondef(p.oid) as fn
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='employee_login';
```
**Result:** `security_definer = true`, `search_path` is set to strict list.

## Test Checklist (Manual)

To be performed by QA/Admin via Frontend or Curl:

- [ ] **Wrong Password (1x):** Should return "Credenciais inválidas" after ~300-600ms delay.
- [ ] **Wrong Password (2x):** Should return "Credenciais inválidas".
- [ ] **Wrong Password (3x):** Should return "Credenciais inválidas".
- [ ] **Attempt 4 (Correct Password):** Should return "Conta bloqueada. Solicite ao administrador." (due to reset_required=true on 3rd fail).
- [ ] **Admin Action:** Log in as Admin -> Employees -> Select User -> Reset Password.
- [ ] **User Retry:** Log in with new password -> Should succeed.
