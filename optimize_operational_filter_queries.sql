-- Stage 7.3: bounded keyset pages for the Kanban operational filters.
--
-- The existing get_operational_queue remains unchanged because it also feeds the
-- Overview groups. This dedicated read API returns card summaries, derives the
-- tenant from the current actor and keeps ticket RLS active.

begin;

create or replace function public.get_operational_ticket_page(
    p_window text default 'all',
    p_basis text default 'auto',
    p_status text default null,
    p_technician_id uuid default null,
    p_search text default null,
    p_limit integer default 20,
    p_cursor jsonb default null,
    p_include_counts boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_tz text := 'America/Sao_Paulo';
    v_today_date date;
    v_today_start timestamptz;
    v_tomorrow_start timestamptz;
    v_day_after_tomorrow_start timestamptz;
    v_in_8_days_start timestamptz;
    v_search text := nullif(btrim(coalesce(p_search, '')), '');
    v_cursor_due_is_null integer;
    v_cursor_due_at timestamptz;
    v_cursor_requested_rank integer;
    v_cursor_priority_rank integer;
    v_cursor_created_at timestamptz;
    v_cursor_id uuid;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_window is null or p_window not in (
        'today', 'today_tomorrow', 'next_7_days', 'overdue', 'no_deadline', 'all'
    ) then
        raise exception 'Janela operacional invalida.';
    end if;
    if p_basis is null or p_basis not in ('auto', 'analysis', 'delivery', 'entry', 'outsourced') then
        raise exception 'Base de data invalida.';
    end if;
    if p_status is not null and p_status <> 'all' and p_status not in (
        'Aberto', 'Terceirizado', 'Analise Tecnica', 'Aprovacao',
        'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente'
    ) then
        raise exception 'Status de OS invalido.';
    end if;
    if p_limit is null or p_limit < 0 or p_limit > 50 then
        raise exception 'O limite deve estar entre 0 e 50.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;

    if p_technician_id is not null and not exists (
        select 1
          from public.employees e
         where e.id = p_technician_id
           and e.workspace_id = v_ctx.workspace_id
           and e.deleted_at is null
    ) then
        raise exception 'Tecnico nao encontrado ou fora da empresa.';
    end if;

    if p_cursor is not null then
        begin
            v_cursor_due_is_null := (p_cursor ->> 'due_is_null')::integer;
            v_cursor_due_at := (p_cursor ->> 'due_at')::timestamptz;
            v_cursor_requested_rank := (p_cursor ->> 'requested_rank')::integer;
            v_cursor_priority_rank := (p_cursor ->> 'priority_rank')::integer;
            v_cursor_created_at := (p_cursor ->> 'created_at')::timestamptz;
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de paginacao invalido.';
        end;

        if v_cursor_due_is_null is null or v_cursor_due_at is null
           or v_cursor_requested_rank is null or v_cursor_priority_rank is null
           or v_cursor_created_at is null or v_cursor_id is null then
            raise exception 'Cursor de paginacao incompleto.';
        end if;
    end if;

    v_today_date := (now() at time zone v_tz)::date;
    v_today_start := v_today_date::timestamp at time zone v_tz;
    v_tomorrow_start := v_today_start + interval '1 day';
    v_day_after_tomorrow_start := v_today_start + interval '2 days';
    v_in_8_days_start := v_today_start + interval '8 days';

    with base_tickets as materialized (
        select
            t.id,
            t.workspace_id,
            t.client_name,
            t.contact_info,
            t.os_number,
            t.entry_date,
            t.deadline,
            t.priority,
            t.device_model,
            t.serial_number,
            t.defect_reported,
            t.device_condition,
            t.status,
            t.previous_status,
            t.tech_notes,
            t.parts_needed,
            t.parts_status,
            t.parts_purchased_at,
            t.parts_received_at,
            t.budget_value,
            t.budget_status,
            t.budget_sent_at,
            t.repair_successful,
            t.repair_start_at,
            t.repair_end_at,
            t.test_start_at,
            t.pickup_available,
            t.pickup_available_at,
            t.created_by,
            t.created_by_name,
            t.created_at,
            t.updated_at,
            case
                when jsonb_typeof(t.test_notes) = 'array' and jsonb_array_length(t.test_notes) > 0
                    then jsonb_build_array(t.test_notes -> -1)
                else '[]'::jsonb
            end as test_notes,
            t.priority_requested,
            t.technician_id,
            t.analysis_deadline,
            t.deleted_at,
            t.delivered_at,
            t.delivery_method,
            t.carrier_name,
            t.tracking_code,
            t.is_outsourced,
            t.outsourced_company_id,
            t.outsourced_deadline,
            t.outsourced_return_count,
            t.outsourced_at,
            t.outsourced_failure_reason,
            t.public_token,
            t.analysis_started_at,
            t.analysis_scheduled,
            t.repair_scheduled,
            t.analysis_scheduled_at,
            t.repair_scheduled_at,
            t.repair_elapsed_seconds,
            t.repair_paused_at,
            t.repair_resume_count,
            t.overview_queue_stage,
            t.overview_queue_entered_at,
            case
                when p_basis = 'analysis' then t.analysis_deadline
                when p_basis = 'delivery' then t.deadline
                when p_basis = 'entry' then t.entry_date
                when p_basis = 'outsourced' then t.outsourced_deadline
                when p_basis = 'auto' then
                    case
                        when t.status = 'Terceirizado' and t.outsourced_deadline is not null then t.outsourced_deadline
                        when t.status in ('Aberto', 'Analise Tecnica') and t.analysis_deadline is not null then t.analysis_deadline
                        when t.status in ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente')
                            and t.deadline is not null then t.deadline
                        else coalesce(t.analysis_deadline, t.deadline, t.outsourced_deadline)
                    end
            end as effective_due_at,
            case
                when p_basis = 'analysis' and t.analysis_deadline is not null then 'analysis'
                when p_basis = 'delivery' and t.deadline is not null then 'delivery'
                when p_basis = 'entry' and t.entry_date is not null then 'entry'
                when p_basis = 'outsourced' and t.outsourced_deadline is not null then 'outsourced'
                when p_basis = 'auto' then
                    case
                        when t.status = 'Terceirizado' and t.outsourced_deadline is not null then 'outsourced'
                        when t.status in ('Aberto', 'Analise Tecnica') and t.analysis_deadline is not null then 'analysis'
                        when t.status in ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente')
                            and t.deadline is not null then 'delivery'
                        when t.analysis_deadline is not null then 'analysis'
                        when t.deadline is not null then 'delivery'
                        when t.outsourced_deadline is not null then 'outsourced'
                        else 'none'
                    end
                else 'none'
            end as effective_due_type
        from public.tickets t
        where t.workspace_id = v_ctx.workspace_id
          and t.deleted_at is null
          and (
              (p_status is null and t.status <> 'Finalizado')
              or (p_status = 'all' and t.status <> 'Finalizado')
              or (p_status is not null and p_status <> 'all' and t.status = p_status)
          )
          and (p_technician_id is null or t.technician_id = p_technician_id)
          and (
              v_search is null
              or t.client_name ilike '%' || v_search || '%'
              or t.os_number ilike '%' || v_search || '%'
              or t.device_model ilike '%' || v_search || '%'
              or coalesce(t.serial_number, '') ilike '%' || v_search || '%'
              or coalesce(t.contact_info, '') ilike '%' || v_search || '%'
          )
    ), bucketed_tickets as materialized (
        select
            bt.*,
            case
                when bt.effective_due_at is null then 'no_deadline'
                when bt.effective_due_at < v_today_start then 'overdue'
                when bt.effective_due_at < v_tomorrow_start then 'today'
                when bt.effective_due_at < v_day_after_tomorrow_start then 'tomorrow'
                when bt.effective_due_at < v_in_8_days_start then 'next_7_days'
                else 'later'
            end as urgency_bucket,
            coalesce(bt.effective_due_at < v_today_start, false) as is_overdue,
            case
                when bt.effective_due_at is not null then
                    (bt.effective_due_at at time zone v_tz)::date
                    - (v_today_start at time zone v_tz)::date
                else null
            end as days_to_due
        from base_tickets bt
    ), windowed_tickets as materialized (
        select *
          from bucketed_tickets bt
         where p_window = 'all'
            or (p_window = 'overdue' and bt.urgency_bucket = 'overdue')
            or (p_window = 'no_deadline' and bt.urgency_bucket = 'no_deadline')
            or (p_window = 'today' and bt.urgency_bucket = 'today')
            or (p_window = 'today_tomorrow' and bt.urgency_bucket in ('today', 'tomorrow'))
            or (p_window = 'next_7_days' and bt.urgency_bucket in ('today', 'tomorrow', 'next_7_days'))
    ), ordered_tickets as materialized (
        select
            wt.*,
            case when wt.effective_due_at is null then 1 else 0 end as due_is_null,
            coalesce(wt.effective_due_at, 'infinity'::timestamptz) as due_sort,
            case
                when wt.priority_requested is true then 0
                when wt.priority_requested is false then 1
                else 2
            end as requested_rank,
            case wt.priority
                when 'Urgente' then 1
                when 'Alta' then 2
                when 'Normal' then 3
                when 'Baixa' then 4
                else 5
            end as priority_rank
        from windowed_tickets wt
    ), after_cursor as (
        select *
          from ordered_tickets ot
         where p_cursor is null
            or (
                ot.due_is_null, ot.due_sort, ot.requested_rank,
                ot.priority_rank, ot.created_at, ot.id
            ) > (
                v_cursor_due_is_null, v_cursor_due_at, v_cursor_requested_rank,
                v_cursor_priority_rank, v_cursor_created_at, v_cursor_id
            )
    ), page_plus_one as materialized (
        select *
          from after_cursor
         order by due_is_null, due_sort, requested_rank, priority_rank, created_at, id
         limit case when p_limit = 0 then 0 else p_limit + 1 end
    ), page_rows as materialized (
        select *
          from page_plus_one
         order by due_is_null, due_sort, requested_rank, priority_rank, created_at, id
         limit p_limit
    ), aggregated_counts as (
        select jsonb_build_object(
            'today', count(*) filter (where urgency_bucket = 'today'),
            'today_tomorrow', count(*) filter (where urgency_bucket in ('today', 'tomorrow')),
            'next_7_days', count(*) filter (where urgency_bucket in ('today', 'tomorrow', 'next_7_days')),
            'overdue', count(*) filter (where urgency_bucket = 'overdue'),
            'no_deadline', count(*) filter (where urgency_bucket = 'no_deadline'),
            'all', count(*)
        ) as counts
        from bucketed_tickets
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(
                (to_jsonb(p)
                    - 'due_is_null' - 'due_sort' - 'requested_rank' - 'priority_rank')
                    || jsonb_build_object('_card_summary', true)
                order by p.due_is_null, p.due_sort, p.requested_rank,
                         p.priority_rank, p.created_at, p.id
            )
            from page_rows p
        ), '[]'::jsonb),
        'total', case when coalesce(p_include_counts, true)
            then (select count(*) from windowed_tickets) else null end,
        'counts', case when coalesce(p_include_counts, true)
            then (select counts from aggregated_counts) else null end,
        'has_more', case when p_limit = 0 then false
            else (select count(*) > p_limit from page_plus_one) end,
        'next_cursor', case
            when p_limit = 0 or not (select count(*) > p_limit from page_plus_one) then null
            else (
                select jsonb_build_object(
                    'due_is_null', p.due_is_null,
                    'due_at', p.due_sort,
                    'requested_rank', p.requested_rank,
                    'priority_rank', p.priority_rank,
                    'created_at', p.created_at,
                    'id', p.id
                )
                from page_rows p
                order by p.due_is_null desc, p.due_sort desc, p.requested_rank desc,
                         p.priority_rank desc, p.created_at desc, p.id desc
                limit 1
            )
        end
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_operational_ticket_page(
    text, text, text, uuid, text, integer, jsonb, boolean
) from public;
grant execute on function public.get_operational_ticket_page(
    text, text, text, uuid, text, integer, jsonb, boolean
) to anon, authenticated;

comment on function public.get_operational_ticket_page(
    text, text, text, uuid, text, integer, jsonb, boolean
) is 'Returns one bounded operational Kanban card page. Tenant context comes from the current actor and ticket RLS remains active.';

commit;
