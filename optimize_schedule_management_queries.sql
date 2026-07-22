-- Stage 7.2: bounded, independently paginated queues for Schedule Management.
--
-- The API never receives a workspace id. It resolves the current actor, requires
-- an administrator, and stays SECURITY INVOKER so the existing ticket, employee,
-- and appointment RLS policies continue to apply.

begin;

create index if not exists idx_tickets_schedule_queue
    on public.tickets (workspace_id, technician_id, entry_date desc, id desc)
    where deleted_at is null
      and status not in ('Teste Final', 'Terceirizado', 'Finalizado', 'Retirada Cliente');

create or replace function public.get_unscheduled_ticket_page(
    p_bucket text default 'assigned',
    p_technician_id uuid default null,
    p_appointment_type text default null,
    p_status text default null,
    p_reference_date date default null,
    p_capacity_full boolean default false,
    p_limit integer default 20,
    p_cursor jsonb default null,
    p_include_total boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_cursor_entry timestamptz;
    v_cursor_id uuid;
    v_reference_date date;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not v_ctx.is_admin then
        raise exception 'Acesso negado: somente administradores gerenciam a agenda geral.';
    end if;
    if p_bucket is null or p_bucket not in ('assigned', 'unassigned', 'late', 'conflict') then
        raise exception 'Grupo de pendencias invalido.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if p_appointment_type is not null and p_appointment_type not in ('analysis', 'repair') then
        raise exception 'Tipo de agendamento invalido.';
    end if;
    if p_status is not null and p_status not in (
        'Aberto', 'Aprovacao', 'Compra Peca', 'Analise Tecnica', 'Andamento Reparo'
    ) then
        raise exception 'Status de OS invalido para a agenda.';
    end if;
    if p_bucket = 'conflict' and p_technician_id is null then
        raise exception 'Selecione um tecnico para consultar conflitos.';
    end if;

    if p_technician_id is not null and not exists (
        select 1
          from public.employees e
         where e.id = p_technician_id
           and e.workspace_id = v_ctx.workspace_id
           and e.deleted_at is null
           and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Tecnico nao encontrado ou fora da empresa.';
    end if;

    if p_cursor is not null then
        begin
            v_cursor_entry := (p_cursor ->> 'entry_date')::timestamptz;
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de paginacao invalido.';
        end;
        if v_cursor_entry is null or v_cursor_id is null then
            raise exception 'Cursor de paginacao incompleto.';
        end if;
    end if;

    v_reference_date := coalesce(
        p_reference_date,
        (now() at time zone 'America/Sao_Paulo')::date
    );

    with base as (
        select
            t.id,
            t.os_number,
            t.client_name,
            t.status,
            t.technician_id,
            e.name as technician_name,
            t.entry_date,
            t.device_model,
            t.priority,
            t.deadline,
            t.analysis_deadline,
            t.defect_reported,
            t.analysis_scheduled_at,
            t.repair_scheduled_at
        from public.tickets t
        left join public.employees e
          on e.id = t.technician_id
         and e.workspace_id = t.workspace_id
         and e.deleted_at is null
        where t.workspace_id = v_ctx.workspace_id
          and t.deleted_at is null
          and t.status not in ('Teste Final', 'Terceirizado', 'Finalizado', 'Retirada Cliente')
          and (p_status is null or t.status = p_status)
          and (
              p_technician_id is null
              or t.technician_id is null
              or t.technician_id = p_technician_id
          )
          and not exists (
              select 1
                from public.ticket_appointments a
               where a.workspace_id = v_ctx.workspace_id
                 and a.ticket_id = t.id
                 and a.deleted_at is null
                 and a.status <> 'cancelled'
                 and (p_appointment_type is null or a.appointment_type = p_appointment_type)
          )
          and case p_bucket
              when 'assigned' then t.technician_id is not null
              when 'unassigned' then t.technician_id is null
              when 'late' then
                  case
                      when t.status = 'Analise Tecnica' then t.analysis_deadline
                      else t.deadline
                  end < now()
              when 'conflict' then
                  coalesce(p_capacity_full, false)
                  and t.technician_id = p_technician_id
                  and case
                      when t.status = 'Analise Tecnica' then t.analysis_deadline
                      else t.deadline
                  end < ((v_reference_date + 1)::timestamp at time zone 'America/Sao_Paulo')
              else false
          end
    ), filtered as (
        select *
          from base b
         where p_cursor is null
            or (b.entry_date, b.id) < (v_cursor_entry, v_cursor_id)
    ), page_plus_one as materialized (
        select *
          from filtered
         order by entry_date desc, id desc
         limit p_limit + 1
    ), page_rows as materialized (
        select *
          from page_plus_one
         order by entry_date desc, id desc
         limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(to_jsonb(p) order by p.entry_date desc, p.id desc)
              from page_rows p
        ), '[]'::jsonb),
        'total', case
            when coalesce(p_include_total, true) then (select count(*) from base)
            else null
        end,
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (
            select jsonb_build_object('entry_date', p.entry_date, 'id', p.id)
              from page_rows p
             order by p.entry_date, p.id
             limit 1
        )
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_unscheduled_ticket_page(
    text, uuid, text, text, date, boolean, integer, jsonb, boolean
) from public;
grant execute on function public.get_unscheduled_ticket_page(
    text, uuid, text, text, date, boolean, integer, jsonb, boolean
) to anon, authenticated;

comment on function public.get_unscheduled_ticket_page(
    text, uuid, text, text, date, boolean, integer, jsonb, boolean
) is 'Returns one bounded Schedule Management queue page. The actor supplies the tenant context and existing RLS remains active.';

commit;
