-- ETAPA 3: sessoes, politica de senhas e bloqueio de contas de funcionarios.
-- Projeto: cpydazjwlmssbzzsurxu
-- Backup de banco: private.security_stage_backups / pre_sessions_password_lockout_20260719
-- Backup de front: backup/pre-session-password-lockout-20260719

begin;

set local statement_timeout = '30s';
set local lock_timeout = '5s';

create schema if not exists private authorization postgres;
revoke all on schema private from public, anon, authenticated;

alter table public.employee_auth_state
    add column if not exists manual_blocked boolean not null default false,
    add column if not exists manual_blocked_at timestamptz,
    add column if not exists manual_block_reason text;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'employee_auth_state_failed_attempts_check'
          and conrelid = 'public.employee_auth_state'::regclass
    ) then
        alter table public.employee_auth_state
            add constraint employee_auth_state_failed_attempts_check
            check (failed_attempts >= 0 and failed_attempts <= 5);
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'employee_auth_state_lock_count_check'
          and conrelid = 'public.employee_auth_state'::regclass
    ) then
        alter table public.employee_auth_state
            add constraint employee_auth_state_lock_count_check
            check (lock_count >= 0);
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'employee_auth_state_reason_length_check'
          and conrelid = 'public.employee_auth_state'::regclass
    ) then
        alter table public.employee_auth_state
            add constraint employee_auth_state_reason_length_check
            check (manual_block_reason is null or length(manual_block_reason) <= 500);
    end if;
end $$;

create unique index if not exists employee_sessions_token_key
    on public.employee_sessions (token);

create index if not exists idx_employee_sessions_active_employee
    on public.employee_sessions (employee_id, expires_at desc)
    where revoked_at is null;

create index if not exists idx_employee_sessions_expiry
    on public.employee_sessions (expires_at)
    where revoked_at is null;

create or replace function private.assert_employee_password(p_password text)
returns void
language plpgsql
set search_path = ''
as $$
begin
    if p_password is null
       or length(p_password) < 8
       or octet_length(p_password) > 72
       or p_password !~ '[[:alpha:]]'
       or p_password !~ '[[:digit:]]' then
        raise exception using
            errcode = '22023',
            message = 'A senha deve ter pelo menos 8 caracteres, no maximo 72 bytes e incluir uma letra e um numero.';
    end if;
end;
$$;

revoke all on function private.assert_employee_password(text) from public, anon, authenticated;

create or replace function private.assert_employee_temporary_password(p_password text)
returns void
language plpgsql
set search_path = ''
as $$
begin
    if p_password is null
       or length(p_password) < 6
       or octet_length(p_password) > 72
       or nullif(btrim(p_password), '') is null then
        raise exception using
            errcode = '22023',
            message = 'A senha temporaria deve ter pelo menos 6 caracteres e no maximo 72 bytes.';
    end if;
end;
$$;

revoke all on function private.assert_employee_temporary_password(text) from public, anon, authenticated;

create or replace function public.current_employee_from_token()
returns table(employee_id uuid, workspace_id uuid, role text[])
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_token_text text;
    v_token uuid;
    v_headers jsonb;
begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
    v_token_text := nullif(btrim(v_headers ->> 'x-employee-token'), '');
    if v_token_text is null then
        return;
    end if;

    begin
        v_token := v_token_text::uuid;
    exception when invalid_text_representation then
        return;
    end;

    return query
    select s.employee_id, e.workspace_id, e.roles
    from public.employee_sessions s
    join public.employees e on e.id = s.employee_id
    left join public.employee_auth_state a on a.employee_id = e.id
    where s.token = v_token
      and s.revoked_at is null
      and s.expires_at > now()
      and e.deleted_at is null
      and not e.must_change_password
      and not coalesce(a.reset_required, false)
      and not coalesce(a.manual_blocked, false)
    limit 1;
end;
$$;

create or replace function public.can_manage_workspace(p_workspace_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid;
begin
    v_user_id := auth.uid();

    if v_user_id is not null then
        if exists (
            select 1 from public.workspaces
            where id = p_workspace_id and owner_id = v_user_id
        ) then
            return true;
        end if;

        if exists (
            select 1 from public.profiles
            where id = v_user_id
              and workspace_id = p_workspace_id
              and role = 'admin'
        ) then
            return true;
        end if;
    end if;

    return exists (
        select 1
        from public.current_employee_from_token() t
        where t.workspace_id = p_workspace_id
          and 'admin' = any(coalesce(t.role, '{}'::text[]))
    );
end;
$$;

create or replace function public.employee_login(
    p_company_code text,
    p_username text,
    p_password text
)
returns table(token uuid, employee_json jsonb, must_change_password boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_workspace public.workspaces%rowtype;
    v_employee public.employees%rowtype;
    v_auth public.employee_auth_state%rowtype;
    v_token uuid;
    v_failed_attempts integer;
    v_lock_minutes integer;
begin
    if p_company_code is null or p_username is null or p_password is null
       or length(p_company_code) > 64
       or length(p_username) > 100
       or length(p_password) > 256 then
        perform extensions.crypt(coalesce(p_password, ''), extensions.gen_salt('bf', 10));
        return;
    end if;

    select w.* into v_workspace
    from public.workspaces w
    where w.company_code = btrim(p_company_code)
    limit 1;

    if v_workspace.id is null then
        perform extensions.crypt(p_password, extensions.gen_salt('bf', 10));
        return;
    end if;

    select e.* into v_employee
    from public.employees e
    where e.workspace_id = v_workspace.id
      and e.username = btrim(p_username)
      and e.deleted_at is null
    limit 1;

    if v_employee.id is null then
        perform extensions.crypt(p_password, extensions.gen_salt('bf', 10));
        return;
    end if;

    insert into public.employee_auth_state (employee_id)
    values (v_employee.id)
    on conflict (employee_id) do nothing;

    select a.* into v_auth
    from public.employee_auth_state a
    where a.employee_id = v_employee.id
    for update;

    if v_auth.manual_blocked or v_auth.reset_required then
        perform pg_catalog.pg_sleep(0.25 + random() * 0.15);
        return;
    end if;

    if v_auth.lock_until is not null and v_auth.lock_until > now() then
        perform pg_catalog.pg_sleep(0.25 + random() * 0.15);
        return;
    end if;

    if v_employee.password_hash <> extensions.crypt(p_password, v_employee.password_hash) then
        v_failed_attempts := least(v_auth.failed_attempts + 1, 5);

        if v_failed_attempts >= 5 then
            update public.employee_auth_state
            set failed_attempts = 5,
                lock_until = null,
                reset_required = true,
                updated_at = now()
            where employee_id = v_employee.id;

            update public.employee_sessions
            set revoked_at = coalesce(revoked_at, now())
            where employee_id = v_employee.id and revoked_at is null;
        elsif v_failed_attempts >= 3 then
            v_lock_minutes := least(15 * power(2, v_auth.lock_count)::integer, 120);
            update public.employee_auth_state
            set failed_attempts = v_failed_attempts,
                lock_count = lock_count + 1,
                lock_until = now() + make_interval(mins => v_lock_minutes),
                updated_at = now()
            where employee_id = v_employee.id;
        else
            update public.employee_auth_state
            set failed_attempts = v_failed_attempts,
                lock_until = null,
                updated_at = now()
            where employee_id = v_employee.id;
        end if;

        perform pg_catalog.pg_sleep(0.20 + random() * 0.10);
        return;
    end if;

    update public.employee_auth_state
    set failed_attempts = 0,
        lock_until = null,
        lock_count = 0,
        reset_required = false,
        updated_at = now()
    where employee_id = v_employee.id;

    insert into public.employee_sessions (employee_id, expires_at, last_seen_at)
    values (v_employee.id, now() + interval '30 days', now())
    returning public.employee_sessions.token into v_token;

    return query
    select v_token,
           jsonb_build_object(
               'id', v_employee.id,
               'employee_id', v_employee.id,
               'name', v_employee.name,
               'username', v_employee.username,
               'roles', v_employee.roles,
               'workspace_id', v_employee.workspace_id,
               'workspace_name', v_workspace.name,
               'company_code', v_workspace.company_code,
               'whatsapp_number', v_workspace.whatsapp_number,
               'tracker_config', v_workspace.tracker_config,
               'must_change_password', v_employee.must_change_password
           ),
           v_employee.must_change_password;
end;
$$;

create or replace function public.validate_employee_session(p_token uuid)
returns table(valid boolean, employee_id uuid, workspace_id uuid, roles text[])
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_session record;
begin
    select s.id, s.employee_id, e.workspace_id, e.roles
    into v_session
    from public.employee_sessions s
    join public.employees e on e.id = s.employee_id
    left join public.employee_auth_state a on a.employee_id = e.id
    where s.token = p_token
      and s.revoked_at is null
      and s.expires_at > now()
      and e.deleted_at is null
      and not coalesce(a.reset_required, false)
      and not coalesce(a.manual_blocked, false)
    limit 1;

    if v_session.id is null then
        return query select false, null::uuid, null::uuid, null::text[];
        return;
    end if;

    update public.employee_sessions
    set last_seen_at = now(),
        expires_at = now() + interval '30 days'
    where id = v_session.id;

    return query
    select true, v_session.employee_id, v_session.workspace_id, v_session.roles;
end;
$$;

create or replace function public.employee_logout(p_token uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.employee_sessions
    set revoked_at = coalesce(revoked_at, now())
    where token = p_token;
end;
$$;

create or replace function public.create_employee(
    p_workspace_id uuid,
    p_name text,
    p_username text,
    p_password text,
    p_roles text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_new_id uuid;
begin
    if not public.can_manage_workspace(p_workspace_id) then
        raise exception 'Permissao negada.';
    end if;

    perform private.assert_employee_temporary_password(p_password);

    if nullif(btrim(p_name), '') is null or nullif(btrim(p_username), '') is null then
        raise exception 'Nome e usuario sao obrigatorios.';
    end if;

    insert into public.employees (
        workspace_id, name, username, password_hash, roles, must_change_password
    ) values (
        p_workspace_id,
        btrim(p_name),
        btrim(p_username),
        extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
        coalesce(p_roles, '{}'::text[]),
        true
    )
    returning id into v_new_id;

    return v_new_id;
end;
$$;

create or replace function public.update_employee(
    p_id uuid,
    p_name text,
    p_username text,
    p_password text,
    p_roles text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_workspace_id uuid;
begin
    select e.workspace_id into v_workspace_id
    from public.employees e where e.id = p_id;

    if v_workspace_id is null then
        raise exception 'Funcionario nao encontrado.';
    end if;
    if not public.can_manage_workspace(v_workspace_id) then
        raise exception 'Permissao negada.';
    end if;
    if nullif(btrim(p_name), '') is null or nullif(btrim(p_username), '') is null then
        raise exception 'Nome e usuario sao obrigatorios.';
    end if;
    if p_password is not null and p_password <> '' then
        perform private.assert_employee_temporary_password(p_password);
    end if;

    update public.employees
    set name = btrim(p_name),
        username = btrim(p_username),
        password_hash = case
            when p_password is not null and p_password <> ''
            then extensions.crypt(p_password, extensions.gen_salt('bf', 10))
            else password_hash
        end,
        must_change_password = case
            when p_password is not null and p_password <> '' then true
            else must_change_password
        end,
        roles = coalesce(p_roles, '{}'::text[])
    where id = p_id;
end;
$$;

create or replace function public.reset_employee_password(
    p_employee_id uuid,
    p_new_password text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_workspace_id uuid;
begin
    select e.workspace_id into v_workspace_id
    from public.employees e where e.id = p_employee_id;

    if v_workspace_id is null then
        raise exception 'Funcionario nao encontrado.';
    end if;
    if not public.can_manage_workspace(v_workspace_id) then
        raise exception 'Permissao negada.';
    end if;

    perform private.assert_employee_temporary_password(p_new_password);

    update public.employees
    set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)),
        must_change_password = true
    where id = p_employee_id;

    insert into public.employee_auth_state (employee_id)
    values (p_employee_id)
    on conflict (employee_id) do update
    set failed_attempts = 0,
        lock_until = null,
        lock_count = 0,
        reset_required = false,
        manual_blocked = false,
        manual_blocked_at = null,
        manual_block_reason = null,
        updated_at = now();
end;
$$;

create or replace function public.employee_change_password(
    p_token uuid,
    p_old_password text,
    p_new_password text
)
returns table(new_token uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_session record;
    v_employee public.employees%rowtype;
begin
    select s.id, s.employee_id
    into v_session
    from public.employee_sessions s
    join public.employees e on e.id = s.employee_id
    left join public.employee_auth_state a on a.employee_id = e.id
    where s.token = p_token
      and s.revoked_at is null
      and s.expires_at > now()
      and e.deleted_at is null
      and not coalesce(a.reset_required, false)
      and not coalesce(a.manual_blocked, false)
    limit 1;

    if v_session.id is null then
        raise exception 'Sessao invalida ou expirada.';
    end if;

    select e.* into v_employee
    from public.employees e where e.id = v_session.employee_id;

    if v_employee.password_hash <> extensions.crypt(p_old_password, v_employee.password_hash) then
        raise exception 'Senha atual incorreta.';
    end if;

    perform private.assert_employee_password(p_new_password);

    if v_employee.password_hash = extensions.crypt(p_new_password, v_employee.password_hash) then
        raise exception 'A nova senha deve ser diferente da senha atual.';
    end if;

    update public.employees
    set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)),
        must_change_password = false
    where id = v_employee.id;

    update public.employee_auth_state
    set failed_attempts = 0,
        lock_until = null,
        lock_count = 0,
        reset_required = false,
        updated_at = now()
    where employee_id = v_employee.id;

    return query select null::uuid;
end;
$$;

create or replace function public.revoke_employee_sessions(p_employee_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_workspace_id uuid;
    v_count integer;
begin
    select e.workspace_id into v_workspace_id
    from public.employees e where e.id = p_employee_id;

    if v_workspace_id is null or not public.can_manage_workspace(v_workspace_id) then
        raise exception 'Permissao negada.';
    end if;

    update public.employee_sessions
    set revoked_at = now()
    where employee_id = p_employee_id and revoked_at is null;
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

create or replace function public.set_employee_account_blocked(
    p_employee_id uuid,
    p_blocked boolean,
    p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_workspace_id uuid;
begin
    select e.workspace_id into v_workspace_id
    from public.employees e where e.id = p_employee_id;

    if v_workspace_id is null or not public.can_manage_workspace(v_workspace_id) then
        raise exception 'Permissao negada.';
    end if;
    if p_blocked and exists (
        select 1
        from public.current_employee_from_token() current_employee
        where current_employee.employee_id = p_employee_id
    ) then
        raise exception 'Voce nao pode bloquear a propria conta.';
    end if;
    if p_reason is not null and length(p_reason) > 500 then
        raise exception 'Motivo muito longo.';
    end if;

    insert into public.employee_auth_state (
        employee_id, failed_attempts, lock_until, lock_count, reset_required,
        manual_blocked, manual_blocked_at, manual_block_reason, updated_at
    ) values (
        p_employee_id, 0, null, 0, false,
        p_blocked,
        case when p_blocked then now() else null end,
        case when p_blocked then nullif(btrim(p_reason), '') else null end,
        now()
    )
    on conflict (employee_id) do update
    set failed_attempts = 0,
        lock_until = null,
        lock_count = 0,
        reset_required = false,
        manual_blocked = excluded.manual_blocked,
        manual_blocked_at = excluded.manual_blocked_at,
        manual_block_reason = excluded.manual_block_reason,
        updated_at = now();

    if p_blocked then
        update public.employee_sessions
        set revoked_at = now()
        where employee_id = p_employee_id and revoked_at is null;
    end if;
end;
$$;

create or replace function public.get_employee_security_status(p_workspace_id uuid)
returns table(
    employee_id uuid,
    failed_attempts integer,
    lock_until timestamptz,
    reset_required boolean,
    manual_blocked boolean,
    manual_blocked_at timestamptz,
    manual_block_reason text,
    active_sessions bigint,
    last_seen_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not public.can_manage_workspace(p_workspace_id) then
        raise exception 'Permissao negada.';
    end if;

    return query
    select e.id,
           coalesce(a.failed_attempts, 0),
           a.lock_until,
           coalesce(a.reset_required, false),
           coalesce(a.manual_blocked, false),
           a.manual_blocked_at,
           a.manual_block_reason,
           count(s.id) filter (
               where s.revoked_at is null
                 and s.expires_at > now()
           ),
           max(s.last_seen_at) filter (where s.revoked_at is null)
    from public.employees e
    left join public.employee_auth_state a on a.employee_id = e.id
    left join public.employee_sessions s on s.employee_id = e.id
    where e.workspace_id = p_workspace_id
      and e.deleted_at is null
    group by e.id, a.failed_attempts, a.lock_until, a.reset_required,
             a.manual_blocked, a.manual_blocked_at, a.manual_block_reason
    order by e.name;
end;
$$;

create or replace function private.revoke_sessions_on_employee_security_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if old.password_hash is distinct from new.password_hash
       or old.roles is distinct from new.roles
       or old.deleted_at is distinct from new.deleted_at then
        update public.employee_sessions
        set revoked_at = now()
        where employee_id = new.id and revoked_at is null;
    end if;
    return new;
end;
$$;

revoke all on function private.revoke_sessions_on_employee_security_change() from public, anon, authenticated;

drop trigger if exists revoke_sessions_on_employee_security_change on public.employees;
create trigger revoke_sessions_on_employee_security_change
after update of password_hash, roles, deleted_at on public.employees
for each row execute function private.revoke_sessions_on_employee_security_change();

-- Sessoes existentes continuam com o prazo que ja possuíam. Novas sessoes e
-- sessoes validadas usam uma janela renovavel de 30 dias, sem limite de aparelhos.

update public.employee_sessions
set revoked_at = now()
where revoked_at is null and expires_at <= now();

revoke execute on function public.employee_login(text, text, text) from public, authenticated;

revoke execute on function public.employee_logout(uuid) from public, authenticated;

revoke execute on function public.validate_employee_session(uuid) from public, authenticated;

revoke execute on function public.employee_change_password(uuid, text, text) from public, authenticated;

revoke execute on function public.current_employee_from_token() from public;

revoke execute on function public.can_manage_workspace(uuid) from public;

revoke execute on function public.create_employee(uuid, text, text, text, text[]) from public;

revoke execute on function public.update_employee(uuid, text, text, text, text[]) from public;

revoke execute on function public.reset_employee_password(uuid, text) from public;

revoke all on function public.revoke_employee_sessions(uuid) from public;
grant execute on function public.revoke_employee_sessions(uuid) to anon, authenticated, service_role;

revoke all on function public.set_employee_account_blocked(uuid, boolean, text) from public;
grant execute on function public.set_employee_account_blocked(uuid, boolean, text) to anon, authenticated, service_role;

revoke all on function public.get_employee_security_status(uuid) from public;
grant execute on function public.get_employee_security_status(uuid) to anon, authenticated, service_role;

notify pgrst, 'reload schema';

commit;
