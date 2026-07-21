-- Stage 4: harden public schedule functions without changing the frontend API.
--
-- The existing implementations are moved to the non-exposed private schema.
-- Public functions keep the same signatures and defaults, but now authorize the
-- current native user or employee token before delegating to the original logic.

begin;

-- Preserve the battle-tested implementations while removing their direct API exposure.
alter function public.get_schedule_availability(uuid, text, date, integer) set schema private;
alter function public.get_unscheduled_tickets(uuid, text, text, integer, integer) set schema private;
alter function public.get_schedule_dashboard(uuid, text, date) set schema private;
alter function public.get_ticket_appointments(uuid) set schema private;
alter function public.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) set schema private;
alter function public.create_ticket_appointment(uuid, uuid, text, timestamptz, timestamptz, text) set schema private;
alter function public.create_schedule_block(uuid, text, timestamptz, timestamptz, boolean, text, jsonb, text) set schema private;
alter function public.delete_schedule_block(uuid) set schema private;

-- Defense in depth: only the function owner may execute the private implementations.
revoke all on function private.get_schedule_availability(uuid, text, date, integer) from public, anon, authenticated, service_role;
revoke all on function private.get_unscheduled_tickets(uuid, text, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function private.get_schedule_dashboard(uuid, text, date) from public, anon, authenticated, service_role;
revoke all on function private.get_ticket_appointments(uuid) from public, anon, authenticated, service_role;
revoke all on function private.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.create_ticket_appointment(uuid, uuid, text, timestamptz, timestamptz, text) from public, anon, authenticated, service_role;
revoke all on function private.create_schedule_block(uuid, text, timestamptz, timestamptz, boolean, text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function private.delete_schedule_block(uuid) from public, anon, authenticated, service_role;

create function public.get_schedule_availability(
    p_technician_id uuid,
    p_mode text,
    p_reference_date date,
    p_days integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_technician_id is null or p_reference_date is null then
        raise exception 'Técnico e data de referência são obrigatórios.';
    end if;
    if p_mode is null or p_mode not in ('analysis', 'repair', 'all') then
        raise exception 'Modo de agenda inválido.';
    end if;
    if p_days is null or p_days < 1 or p_days > 31 then
        raise exception 'O período da agenda deve ter entre 1 e 31 dias.';
    end if;
    if not exists (
        select 1
        from public.employees e
        where e.id = p_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;
    if not (v_ctx.is_admin or v_ctx.is_attendant or
            (v_ctx.is_technician and v_ctx.actor_employee_id = p_technician_id)) then
        raise exception 'Acesso negado à agenda deste técnico.';
    end if;

    return private.get_schedule_availability(
        p_technician_id, p_mode, p_reference_date, p_days
    );
end;
$$;

create function public.get_unscheduled_tickets(
    p_technician_id uuid default null,
    p_appointment_type text default null,
    p_status text default null,
    p_limit integer default 50,
    p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not v_ctx.is_admin then
        raise exception 'Acesso negado: somente administradores gerenciam a agenda geral.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 then
        raise exception 'Paginação inválida.';
    end if;
    if p_appointment_type is not null and p_appointment_type not in ('analysis', 'repair') then
        raise exception 'Tipo de agendamento inválido.';
    end if;
    if p_technician_id is not null and not exists (
        select 1 from public.employees e
        where e.id = p_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;

    return private.get_unscheduled_tickets(
        p_technician_id, p_appointment_type, p_status, p_limit, p_offset
    );
end;
$$;

create function public.get_schedule_dashboard(
    p_technician_id uuid default null,
    p_view text default 'day',
    p_reference_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not v_ctx.is_admin then
        raise exception 'Acesso negado: somente administradores gerenciam a agenda geral.';
    end if;
    if p_technician_id is not null and not exists (
        select 1 from public.employees e
        where e.id = p_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;

    return private.get_schedule_dashboard(p_technician_id, p_view, p_reference_date);
end;
$$;

create function public.get_ticket_appointments(p_ticket_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket record;
    v_is_tester boolean;
begin
    select * into v_ctx from public.get_current_actor_context();
    v_is_tester := 'tester' = any(coalesce(v_ctx.actor_roles, '{}'::text[]));

    select t.technician_id, t.status
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Chamado não encontrado ou não pertence ao workspace.';
    end if;
    if not (
        v_ctx.is_admin
        or v_ctx.is_attendant
        or (
            v_ctx.is_technician and (
                v_ticket.technician_id = v_ctx.actor_employee_id
                or (v_ticket.technician_id is null and
                    v_ticket.status in ('Analise Tecnica', 'Andamento Reparo', 'Teste Final'))
            )
        )
        or (v_is_tester and v_ticket.status = 'Teste Final')
    ) then
        raise exception 'Acesso negado aos agendamentos deste chamado.';
    end if;

    return private.get_ticket_appointments(p_ticket_id);
end;
$$;

create function public.create_ticket_with_optional_analysis_schedule(
    p_ticket jsonb,
    p_appointment jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_technician_id uuid;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket is null or jsonb_typeof(p_ticket) <> 'object' then
        raise exception 'Os dados do chamado são obrigatórios.';
    end if;
    if p_appointment is not null and jsonb_typeof(p_appointment) <> 'object' then
        raise exception 'Os dados do agendamento são inválidos.';
    end if;

    if nullif(p_ticket->>'technician_id', '') is not null then
        begin
            v_technician_id := (p_ticket->>'technician_id')::uuid;
        exception when invalid_text_representation then
            raise exception 'Técnico inválido.';
        end;
    end if;

    if not (v_ctx.is_admin or v_ctx.is_attendant) then
        if not v_ctx.is_technician or v_technician_id is distinct from v_ctx.actor_employee_id then
            raise exception 'Acesso negado para criar este chamado.';
        end if;
    end if;

    if v_technician_id is not null and not exists (
        select 1 from public.employees e
        where e.id = v_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;

    return private.create_ticket_with_optional_analysis_schedule(p_ticket, p_appointment);
end;
$$;

create function public.create_ticket_appointment(
    p_ticket_id uuid,
    p_technician_id uuid,
    p_appointment_type text,
    p_scheduled_start timestamptz,
    p_scheduled_end timestamptz,
    p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket_id is null or p_technician_id is null then
        raise exception 'Chamado e técnico são obrigatórios.';
    end if;
    if p_appointment_type is null or p_appointment_type not in ('analysis', 'repair') then
        raise exception 'Tipo de agendamento inválido. Use analysis ou repair.';
    end if;
    if p_scheduled_start is null or p_scheduled_end is null or p_scheduled_end <= p_scheduled_start then
        raise exception 'Período do agendamento inválido.';
    end if;

    select t.technician_id, t.status
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Chamado não encontrado ou não pertence ao workspace.';
    end if;
    if not exists (
        select 1 from public.employees e
        where e.id = p_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;

    if not (v_ctx.is_admin or v_ctx.is_attendant) then
        if not v_ctx.is_technician
           or p_technician_id <> v_ctx.actor_employee_id
           or not (
               v_ticket.technician_id = v_ctx.actor_employee_id
               or (v_ticket.technician_id is null and
                   v_ticket.status in ('Analise Tecnica', 'Andamento Reparo', 'Teste Final'))
           ) then
            raise exception 'Acesso negado para criar este agendamento.';
        end if;
    end if;

    return private.create_ticket_appointment(
        p_ticket_id, p_technician_id, p_appointment_type,
        p_scheduled_start, p_scheduled_end, p_notes
    );
end;
$$;

create function public.create_schedule_block(
    p_technician_id uuid,
    p_block_type text,
    p_start_at timestamptz,
    p_end_at timestamptz,
    p_is_recurring boolean default false,
    p_recurrence_type text default null,
    p_recurrence_days jsonb default null,
    p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not exists (
        select 1 from public.employees e
        where e.id = p_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;
    if not (v_ctx.is_admin or
            (v_ctx.is_technician and v_ctx.actor_employee_id = p_technician_id)) then
        raise exception 'Acesso negado para bloquear esta agenda.';
    end if;

    return private.create_schedule_block(
        p_technician_id, p_block_type, p_start_at, p_end_at,
        p_is_recurring, p_recurrence_type, p_recurrence_days, p_reason
    );
end;
$$;

create function public.delete_schedule_block(p_block_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_technician_id uuid;
begin
    select * into v_ctx from public.get_current_actor_context();

    select b.technician_id
      into v_technician_id
      from public.technician_schedule_blocks b
     where b.id = p_block_id
       and b.workspace_id = v_ctx.workspace_id;

    if not found then
        raise exception 'Bloqueio não encontrado ou não pertence ao workspace.';
    end if;
    if not (v_ctx.is_admin or
            (v_ctx.is_technician and v_ctx.actor_employee_id = v_technician_id)) then
        raise exception 'Acesso negado para remover este bloqueio.';
    end if;

    return private.delete_schedule_block(p_block_id);
end;
$$;

-- API functions remain callable by native sessions and employee-token sessions.
-- PUBLIC is revoked so calls cannot inherit execution accidentally.
revoke all on function public.get_schedule_availability(uuid, text, date, integer) from public;
revoke all on function public.get_unscheduled_tickets(uuid, text, text, integer, integer) from public;
revoke all on function public.get_schedule_dashboard(uuid, text, date) from public;
revoke all on function public.get_ticket_appointments(uuid) from public;
revoke all on function public.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) from public;
revoke all on function public.create_ticket_appointment(uuid, uuid, text, timestamptz, timestamptz, text) from public;
revoke all on function public.create_schedule_block(uuid, text, timestamptz, timestamptz, boolean, text, jsonb, text) from public;
revoke all on function public.delete_schedule_block(uuid) from public;

grant execute on function public.get_schedule_availability(uuid, text, date, integer) to anon, authenticated, service_role;
grant execute on function public.get_unscheduled_tickets(uuid, text, text, integer, integer) to anon, authenticated, service_role;
grant execute on function public.get_schedule_dashboard(uuid, text, date) to anon, authenticated, service_role;
grant execute on function public.get_ticket_appointments(uuid) to anon, authenticated, service_role;
grant execute on function public.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) to anon, authenticated, service_role;
grant execute on function public.create_ticket_appointment(uuid, uuid, text, timestamptz, timestamptz, text) to anon, authenticated, service_role;
grant execute on function public.create_schedule_block(uuid, text, timestamptz, timestamptz, boolean, text, jsonb, text) to anon, authenticated, service_role;
grant execute on function public.delete_schedule_block(uuid) to anon, authenticated, service_role;

-- Remove inherited PUBLIC execution from the remaining external schedule RPCs.
revoke all on function public.cancel_ticket_appointment(uuid, text) from public;
revoke all on function public.reschedule_ticket_appointment(uuid, uuid, timestamptz, timestamptz, text) from public;
revoke all on function public.start_ticket_appointment(uuid, text) from public;
revoke all on function public.complete_ticket_appointment(uuid, text) from public;
revoke all on function public.get_technician_schedule(uuid, text, date) from public;

grant execute on function public.cancel_ticket_appointment(uuid, text) to anon, authenticated, service_role;
grant execute on function public.reschedule_ticket_appointment(uuid, uuid, timestamptz, timestamptz, text) to anon, authenticated, service_role;
grant execute on function public.start_ticket_appointment(uuid, text) to anon, authenticated, service_role;
grant execute on function public.complete_ticket_appointment(uuid, text) to anon, authenticated, service_role;
grant execute on function public.get_technician_schedule(uuid, text, date) to anon, authenticated, service_role;

-- Internal helpers and trigger functions must never be direct PostgREST endpoints.
revoke all on function public.get_ticket_appointments_state(uuid, uuid) from public, anon, authenticated;
revoke all on function public.get_expanded_blocks(uuid, uuid, date, date) from public, anon, authenticated;
revoke all on function public.validate_appointment_capacity(uuid, uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.enforce_configurable_appointment() from public, anon, authenticated;
revoke all on function public.sync_ticket_schedule_state() from public, anon, authenticated;
revoke all on function public.set_schedule_updated_at() from public, anon, authenticated;

commit;
