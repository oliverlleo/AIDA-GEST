-- Complemento da etapa de sessoes e bloqueio.
-- Remove a exposicao direta das tabelas de seguranca e mantem o acesso somente
-- pelas RPCs administrativas que validam workspace e cargo.

begin;

set local statement_timeout = '30s';
set local lock_timeout = '5s';

alter function public.revoke_employee_sessions(uuid) security definer;
alter function public.set_employee_account_blocked(uuid, boolean, text) security definer;
alter function public.get_employee_security_status(uuid) security definer;

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

notify pgrst, 'reload schema';

commit;
