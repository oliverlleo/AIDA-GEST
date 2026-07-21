-- Stage 5: prevent duplicate and concurrent schedule mutations.
--
-- The public API signatures remain unchanged. Transaction-level advisory locks
-- serialize capacity checks per technician, row locks serialize mutations of the
-- same appointment, and a partial unique index protects one active appointment
-- per ticket/stage even when a privileged client writes directly to the table.

begin;

-- There are no duplicate active ticket/stage rows before this migration.
-- This index is the final database guarantee if a caller bypasses the RPC checks.
create unique index if not exists ticket_appointments_active_ticket_type_uidx
    on public.ticket_appointments (workspace_id, ticket_id, appointment_type)
    where deleted_at is null and status <> 'cancelled';

create or replace function public.validate_appointment_capacity(
    p_workspace_id uuid,
    p_technician_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz,
    p_exclude_appointment_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_tz text := 'America/Sao_Paulo';
    v_start_date date;
    v_end_date date;
    v_settings record;
    v_max_per_day integer;
    v_max_per_slot integer;
    v_daily_apps integer;
    v_overlapping_apps integer;
    v_overlapping_blocks integer;
begin
    if p_workspace_id is null or p_technician_id is null
       or p_start_at is null or p_end_at is null then
        raise exception 'Técnico, início e término são obrigatórios.';
    end if;

    if p_start_at < pg_catalog.now() then
        raise exception 'Não é permitido agendar em horários no passado.';
    end if;

    v_start_date := pg_catalog.date_trunc('day', p_start_at at time zone v_tz)::date;
    v_end_date := pg_catalog.date_trunc('day', p_end_at at time zone v_tz)::date;

    if v_start_date <> v_end_date then
        raise exception 'Agendamento não pode cruzar a meia-noite.';
    end if;

    if p_end_at <= p_start_at then
        raise exception 'Horário de término deve ser maior que o horário de início.';
    end if;

    -- One short transaction-level lock coordinates every capacity check for the
    -- same workspace/technician. It is released automatically on commit/rollback.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            pg_catalog.concat_ws(
                ':', 'aida_schedule', p_workspace_id::text, p_technician_id::text
            ),
            0
        )
    );

    select *
      into v_settings
      from public.technician_schedule_settings s
     where s.technician_id = p_technician_id
       and s.workspace_id = p_workspace_id
       and s.deleted_at is null
     limit 1;

    if v_settings is null then
        v_max_per_day := 8;
        v_max_per_slot := 1;
    else
        if v_settings.settings is not null and v_settings.settings ? 'maxConcurrent' then
            v_max_per_slot := (v_settings.settings->>'maxConcurrent')::integer;
        else
            v_max_per_slot := coalesce(v_settings.max_appointments_per_slot, 1);
        end if;

        if v_settings.settings is not null and v_settings.settings ? 'maxPerDay' then
            v_max_per_day := (v_settings.settings->>'maxPerDay')::integer;
        else
            v_max_per_day := coalesce(v_settings.max_appointments_per_day, 8);
        end if;
    end if;

    select count(*)
      into v_daily_apps
      from public.ticket_appointments a
     where a.workspace_id = p_workspace_id
       and a.technician_id = p_technician_id
       and a.deleted_at is null
       and a.status <> 'cancelled'
       and pg_catalog.date_trunc('day', a.scheduled_start at time zone v_tz)::date = v_start_date
       and (p_exclude_appointment_id is null or a.id <> p_exclude_appointment_id);

    if v_daily_apps >= v_max_per_day then
        raise exception 'Capacidade diária máxima (%) atingida para o técnico.', v_max_per_day;
    end if;

    select count(*)
      into v_overlapping_apps
      from public.ticket_appointments a
     where a.workspace_id = p_workspace_id
       and a.technician_id = p_technician_id
       and a.deleted_at is null
       and a.status <> 'cancelled'
       and a.scheduled_start < p_end_at
       and a.scheduled_end > p_start_at
       and (p_exclude_appointment_id is null or a.id <> p_exclude_appointment_id);

    if v_overlapping_apps >= v_max_per_slot then
        raise exception 'Capacidade máxima do slot (%) atingida neste horário.', v_max_per_slot;
    end if;

    select count(*)
      into v_overlapping_blocks
      from public.get_expanded_blocks(
          p_workspace_id, p_technician_id, v_start_date, v_end_date
      ) b
     where b.start_at < p_end_at
       and b.end_at > p_start_at;

    if v_overlapping_blocks > 0 then
        raise exception 'Horário conflitante com um bloqueio na agenda do técnico.';
    end if;
end;
$$;

-- Protect direct privileged INSERT/UPDATE operations as well as the regular RPCs.
create or replace function public.enforce_appointment_capacity_concurrently()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_should_validate boolean := false;
begin
    if tg_op = 'INSERT' then
        v_should_validate := true;
    else
        v_should_validate :=
            old.workspace_id is distinct from new.workspace_id
            or old.technician_id is distinct from new.technician_id
            or old.scheduled_start is distinct from new.scheduled_start
            or old.scheduled_end is distinct from new.scheduled_end
            or old.deleted_at is distinct from new.deleted_at
            or (
                old.status = 'cancelled'
                and new.status <> 'cancelled'
            );
    end if;

    if v_should_validate
       and new.deleted_at is null
       and new.status <> 'cancelled' then
        perform public.validate_appointment_capacity(
            new.workspace_id,
            new.technician_id,
            new.scheduled_start,
            new.scheduled_end,
            case when tg_op = 'UPDATE' then new.id else null end
        );
    end if;

    return new;
end;
$$;

revoke all on function public.enforce_appointment_capacity_concurrently()
    from public, anon, authenticated, service_role;

drop trigger if exists trg_ticket_appointments_concurrent_capacity
    on public.ticket_appointments;

create trigger trg_ticket_appointments_concurrent_capacity
before insert or update of
    workspace_id, technician_id, scheduled_start, scheduled_end, status, deleted_at
on public.ticket_appointments
for each row
execute function public.enforce_appointment_capacity_concurrently();

-- Serialize two requests attempting to create the same ticket/stage. The
-- original private implementation then returns its existing friendly message.
create or replace function public.create_ticket_appointment(
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

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            pg_catalog.concat_ws(
                ':', 'aida_ticket_appointment', p_ticket_id::text, p_appointment_type
            ),
            0
        )
    );

    return private.create_ticket_appointment(
        p_ticket_id, p_technician_id, p_appointment_type,
        p_scheduled_start, p_scheduled_end, p_notes
    );
end;
$$;

-- Keep the original mutation logic intact in private and add short row-locking
-- wrappers. This prevents cancel/start/complete/reschedule from overwriting each
-- other when they target the same appointment at the same time.
alter function public.reschedule_ticket_appointment(
    uuid, uuid, timestamptz, timestamptz, text
) set schema private;
alter function public.cancel_ticket_appointment(uuid, text) set schema private;
alter function public.start_ticket_appointment(uuid, text) set schema private;
alter function public.complete_ticket_appointment(uuid, text) set schema private;

revoke all on function private.reschedule_ticket_appointment(
    uuid, uuid, timestamptz, timestamptz, text
) from public, anon, authenticated, service_role;
revoke all on function private.cancel_ticket_appointment(uuid, text)
    from public, anon, authenticated, service_role;
revoke all on function private.start_ticket_appointment(uuid, text)
    from public, anon, authenticated, service_role;
revoke all on function private.complete_ticket_appointment(uuid, text)
    from public, anon, authenticated, service_role;

create function public.reschedule_ticket_appointment(
    p_appointment_id uuid,
    p_technician_id uuid,
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
begin
    select * into v_ctx from public.get_current_actor_context();

    perform 1
      from public.ticket_appointments a
     where a.id = p_appointment_id
       and a.workspace_id = v_ctx.workspace_id
       and a.deleted_at is null
       and a.status <> 'cancelled'
     for update;

    if not found then
        raise exception 'Agendamento não encontrado, inativo ou já cancelado.';
    end if;

    return private.reschedule_ticket_appointment(
        p_appointment_id, p_technician_id,
        p_scheduled_start, p_scheduled_end, p_notes
    );
end;
$$;

create function public.cancel_ticket_appointment(
    p_appointment_id uuid,
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

    perform 1
      from public.ticket_appointments a
     where a.id = p_appointment_id
       and a.workspace_id = v_ctx.workspace_id
       and a.deleted_at is null
       and a.status <> 'cancelled'
     for update;

    if not found then
        raise exception 'Agendamento não encontrado, inativo ou já cancelado.';
    end if;

    return private.cancel_ticket_appointment(p_appointment_id, p_reason);
end;
$$;

create function public.start_ticket_appointment(p_ticket_id uuid, p_type text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_appointment_id uuid;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_type is null or p_type not in ('analysis', 'repair') then
        raise exception 'Tipo de agendamento inválido.';
    end if;

    select a.id
      into v_appointment_id
      from public.ticket_appointments a
     where a.workspace_id = v_ctx.workspace_id
       and a.ticket_id = p_ticket_id
       and a.appointment_type = p_type
       and a.status = 'scheduled'
       and a.deleted_at is null
     order by a.created_at desc
     limit 1
     for update;

    if v_appointment_id is null then
        return;
    end if;

    perform private.start_ticket_appointment(p_ticket_id, p_type);
end;
$$;

create function public.complete_ticket_appointment(p_ticket_id uuid, p_type text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_appointment_id uuid;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_type is null or p_type not in ('analysis', 'repair') then
        raise exception 'Tipo de agendamento inválido.';
    end if;

    select a.id
      into v_appointment_id
      from public.ticket_appointments a
     where a.workspace_id = v_ctx.workspace_id
       and a.ticket_id = p_ticket_id
       and a.appointment_type = p_type
       and a.status in ('scheduled', 'in_progress')
       and a.deleted_at is null
     order by a.created_at desc
     limit 1
     for update;

    if v_appointment_id is null then
        return;
    end if;

    perform private.complete_ticket_appointment(p_ticket_id, p_type);
end;
$$;

revoke all on function public.reschedule_ticket_appointment(
    uuid, uuid, timestamptz, timestamptz, text
) from public;
revoke all on function public.cancel_ticket_appointment(uuid, text) from public;
revoke all on function public.start_ticket_appointment(uuid, text) from public;
revoke all on function public.complete_ticket_appointment(uuid, text) from public;

grant execute on function public.reschedule_ticket_appointment(
    uuid, uuid, timestamptz, timestamptz, text
) to anon, authenticated, service_role;
grant execute on function public.cancel_ticket_appointment(uuid, text)
    to anon, authenticated, service_role;
grant execute on function public.start_ticket_appointment(uuid, text)
    to anon, authenticated, service_role;
grant execute on function public.complete_ticket_appointment(uuid, text)
    to anon, authenticated, service_role;

commit;
