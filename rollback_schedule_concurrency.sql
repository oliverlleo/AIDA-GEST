-- Emergency rollback for harden_schedule_concurrency.sql.
-- Uses the pre-stage snapshot for functions that were replaced in place.

begin;

drop trigger if exists trg_ticket_appointments_concurrent_capacity
    on public.ticket_appointments;
drop function if exists public.enforce_appointment_capacity_concurrently();
drop index if exists public.ticket_appointments_active_ticket_type_uidx;

drop function if exists public.reschedule_ticket_appointment(
    uuid, uuid, timestamptz, timestamptz, text
);
drop function if exists public.cancel_ticket_appointment(uuid, text);
drop function if exists public.start_ticket_appointment(uuid, text);
drop function if exists public.complete_ticket_appointment(uuid, text);

alter function private.reschedule_ticket_appointment(
    uuid, uuid, timestamptz, timestamptz, text
) set schema public;
alter function private.cancel_ticket_appointment(uuid, text) set schema public;
alter function private.start_ticket_appointment(uuid, text) set schema public;
alter function private.complete_ticket_appointment(uuid, text) set schema public;

grant execute on function public.reschedule_ticket_appointment(
    uuid, uuid, timestamptz, timestamptz, text
) to anon, authenticated, service_role;
grant execute on function public.cancel_ticket_appointment(uuid, text)
    to anon, authenticated, service_role;
grant execute on function public.start_ticket_appointment(uuid, text)
    to anon, authenticated, service_role;
grant execute on function public.complete_ticket_appointment(uuid, text)
    to anon, authenticated, service_role;

do $rollback$
declare
    v_snapshot jsonb;
    v_definition text;
begin
    select b.snapshot
      into v_snapshot
      from private.security_stage_backups b
     where b.label = 'pre_schedule_concurrency_20260721'
     order by b.created_at desc
     limit 1;

    if v_snapshot is null then
        raise exception 'Backup pre_schedule_concurrency_20260721 não encontrado.';
    end if;

    select item->>'definition'
      into v_definition
      from jsonb_array_elements(v_snapshot->'functions') item
     where item->>'schema' = 'public'
       and item->>'signature' like 'create_ticket_appointment(%'
     limit 1;

    if v_definition is null then
        raise exception 'Definição anterior de create_ticket_appointment não encontrada.';
    end if;
    execute v_definition;

    select item->>'definition'
      into v_definition
      from jsonb_array_elements(v_snapshot->'functions') item
     where item->>'schema' = 'public'
       and item->>'signature' like 'validate_appointment_capacity(%'
     limit 1;

    if v_definition is null then
        raise exception 'Definição anterior de validate_appointment_capacity não encontrada.';
    end if;
    execute v_definition;
end
$rollback$;

commit;
