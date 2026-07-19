-- REVERSAO DA ETAPA 3.
-- Restaura as nove funcoes capturadas antes da alteracao e remove apenas os
-- objetos novos desta etapa. Sessoes revogadas depois da implantacao nunca sao
-- reativadas pelo rollback.

begin;

set local statement_timeout = '30s';
set local lock_timeout = '5s';

drop trigger if exists revoke_sessions_on_employee_security_change on public.employees;
drop function if exists private.revoke_sessions_on_employee_security_change();

drop function if exists public.get_employee_security_status(uuid);
drop function if exists public.set_employee_account_blocked(uuid, boolean, text);
drop function if exists public.revoke_employee_sessions(uuid);
drop function if exists private.assert_employee_temporary_password(text);
drop function if exists private.assert_employee_password(text);

revoke select (
    employee_id, failed_attempts, lock_until, lock_count, reset_required,
    updated_at, manual_blocked, manual_blocked_at, manual_block_reason
) on public.employee_auth_state from anon, authenticated;
revoke insert (
    employee_id, failed_attempts, lock_until, lock_count, reset_required,
    updated_at, manual_blocked, manual_blocked_at, manual_block_reason
) on public.employee_auth_state from anon, authenticated;
revoke update (
    failed_attempts, lock_until, lock_count, reset_required,
    updated_at, manual_blocked, manual_blocked_at, manual_block_reason
) on public.employee_auth_state from anon, authenticated;
revoke select (id, employee_id, created_at, expires_at, revoked_at, last_seen_at)
on public.employee_sessions from anon, authenticated;
revoke update (revoked_at) on public.employee_sessions from anon, authenticated;

drop policy if exists "Employee admins read auth state" on public.employee_auth_state;
drop policy if exists "Employee admins insert auth state" on public.employee_auth_state;
drop policy if exists "Employee admins update auth state" on public.employee_auth_state;
drop policy if exists "Employee admins read sessions" on public.employee_sessions;
drop policy if exists "Employee admins revoke sessions" on public.employee_sessions;

do $$
declare
    v_function jsonb;
begin
    for v_function in
        select value
        from private.security_stage_backups b,
             jsonb_array_elements(b.snapshot -> 'functions')
        where b.label = 'pre_sessions_password_lockout_20260719'
    loop
        execute v_function ->> 'definition';
    end loop;
end $$;

-- Permissoes anteriores confirmadas no snapshot.
revoke execute on function public.employee_login(text, text, text) from public, authenticated;
grant execute on function public.employee_login(text, text, text) to anon, service_role;

revoke execute on function public.employee_logout(uuid) from public, authenticated;
grant execute on function public.employee_logout(uuid) to anon, service_role;

revoke execute on function public.validate_employee_session(uuid) from public, authenticated;
grant execute on function public.validate_employee_session(uuid) to anon, service_role;

revoke execute on function public.employee_change_password(uuid, text, text) from public, authenticated;
grant execute on function public.employee_change_password(uuid, text, text) to anon, service_role;

revoke execute on function public.current_employee_from_token() from public;
grant execute on function public.current_employee_from_token() to anon, authenticated, service_role;

grant execute on function public.can_manage_workspace(uuid) to public, anon, authenticated, service_role;

revoke execute on function public.create_employee(uuid, text, text, text, text[]) from public;
grant execute on function public.create_employee(uuid, text, text, text, text[]) to anon, authenticated, service_role;

revoke execute on function public.update_employee(uuid, text, text, text, text[]) from public;
grant execute on function public.update_employee(uuid, text, text, text, text[]) to anon, authenticated, service_role;

revoke execute on function public.reset_employee_password(uuid, text) from public;
grant execute on function public.reset_employee_password(uuid, text) to anon, authenticated, service_role;

do $$
declare
    v_session jsonb;
begin
    for v_session in
        select value
        from private.security_stage_backups b,
             jsonb_array_elements(b.snapshot -> 'active_session_state')
        where b.label = 'pre_sessions_password_lockout_20260719'
    loop
        update public.employee_sessions
        set expires_at = (v_session ->> 'expires_at')::timestamptz,
            last_seen_at = (v_session ->> 'last_seen_at')::timestamptz
        where id = (v_session ->> 'id')::uuid
          and revoked_at is null;
    end loop;
end $$;

drop index if exists public.idx_employee_sessions_expiry;
drop index if exists public.idx_employee_sessions_active_employee;
drop index if exists public.employee_sessions_token_key;

alter table public.employee_auth_state
    drop constraint if exists employee_auth_state_reason_length_check,
    drop constraint if exists employee_auth_state_lock_count_check,
    drop constraint if exists employee_auth_state_failed_attempts_check,
    drop column if exists manual_block_reason,
    drop column if exists manual_blocked_at,
    drop column if exists manual_blocked;

notify pgrst, 'reload schema';

commit;
