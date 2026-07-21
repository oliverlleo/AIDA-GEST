-- Stage 7.1: bounded ticket-card reads for boards that must scale to thousands of OS.
--
-- The API never accepts a workspace id. The current native user or employee token
-- resolves the workspace, while SECURITY INVOKER keeps the tickets RLS policies in
-- force. Large JSON/photo fields are fetched only when the OS modal is opened.

begin;

create or replace function public.get_ticket_cards_page(
    p_status text,
    p_scope text default 'kanban',
    p_technician_id uuid default null,
    p_search text default null,
    p_limit integer default 20,
    p_cursor jsonb default null,
    p_use_priority boolean default true,
    p_use_analysis_appointment boolean default true,
    p_use_repair_appointment boolean default true,
    p_use_analysis_deadline boolean default true,
    p_use_delivery_deadline boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_search text := nullif(btrim(coalesce(p_search, '')), '');
    v_cursor_priority integer;
    v_cursor_effective timestamptz;
    v_cursor_deadline timestamptz;
    v_cursor_created timestamptz;
    v_cursor_id uuid;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_status is null or p_status not in (
        'Aberto', 'Terceirizado', 'Analise Tecnica', 'Aprovacao',
        'Compra Peca', 'Andamento Reparo', 'Teste Final',
        'Retirada Cliente', 'Finalizado'
    ) then
        raise exception 'Status de OS invalido.';
    end if;
    if p_scope not in ('kanban', 'bench') then
        raise exception 'Escopo de consulta invalido.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;

    if p_technician_id is not null then
        if not v_ctx.is_admin then
            raise exception 'Somente administradores podem filtrar outro tecnico.';
        end if;
        if not exists (
            select 1
              from public.employees e
             where e.id = p_technician_id
               and e.workspace_id = v_ctx.workspace_id
               and e.deleted_at is null
               and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
        ) then
            raise exception 'Tecnico nao encontrado ou fora da empresa.';
        end if;
    end if;

    if p_scope = 'bench'
       and not (v_ctx.is_admin or v_ctx.is_technician) then
        raise exception 'Acesso negado a bancada tecnica.';
    end if;

    if p_cursor is not null then
        begin
            v_cursor_priority := (p_cursor ->> 'priority_rank')::integer;
            v_cursor_effective := (p_cursor ->> 'effective_at')::timestamptz;
            v_cursor_deadline := (p_cursor ->> 'deadline_at')::timestamptz;
            v_cursor_created := (p_cursor ->> 'created_at')::timestamptz;
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de paginacao invalido.';
        end;
        if v_cursor_priority is null or v_cursor_effective is null or v_cursor_deadline is null
           or v_cursor_created is null or v_cursor_id is null then
            raise exception 'Cursor de paginacao incompleto.';
        end if;
    end if;

    with base as materialized (
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
            case when coalesce(p_use_priority, true)
                       and coalesce(t.priority_requested, false)
                 then 0 else 1 end as priority_rank,
            coalesce(
                case
                    when t.status = 'Analise Tecnica' and coalesce(p_use_analysis_appointment, true)
                        then t.analysis_scheduled_at
                    when t.status = 'Andamento Reparo' and coalesce(p_use_repair_appointment, true)
                        then t.repair_scheduled_at
                    when t.status not in ('Analise Tecnica', 'Andamento Reparo')
                         and coalesce(p_use_repair_appointment, true)
                        then t.repair_scheduled_at
                end,
                case
                    when t.status not in ('Analise Tecnica', 'Andamento Reparo')
                         and coalesce(p_use_analysis_appointment, true)
                        then t.analysis_scheduled_at
                end,
                case
                    when t.status = 'Analise Tecnica' and coalesce(p_use_analysis_deadline, true)
                        then t.analysis_deadline
                    when t.status <> 'Analise Tecnica' and coalesce(p_use_delivery_deadline, true)
                        then t.deadline
                end,
                case
                    when t.status = 'Analise Tecnica' and coalesce(p_use_delivery_deadline, true)
                        then t.deadline
                    when t.status <> 'Analise Tecnica' and coalesce(p_use_analysis_deadline, true)
                        then t.analysis_deadline
                end,
                t.created_at
            ) as effective_sort_at,
            coalesce(
                case
                    when t.status = 'Analise Tecnica' and coalesce(p_use_analysis_deadline, true)
                        then t.analysis_deadline
                    when t.status <> 'Analise Tecnica' and coalesce(p_use_delivery_deadline, true)
                        then t.deadline
                end,
                case
                    when t.status = 'Analise Tecnica' and coalesce(p_use_delivery_deadline, true)
                        then t.deadline
                    when t.status <> 'Analise Tecnica' and coalesce(p_use_analysis_deadline, true)
                        then t.analysis_deadline
                end,
                t.created_at
            ) as deadline_sort_at
        from public.tickets t
        where t.workspace_id = v_ctx.workspace_id
          and t.deleted_at is null
          and t.status = p_status
          and (
              p_scope <> 'bench'
              or (
                  case
                      when v_ctx.is_admin then p_technician_id is null or t.technician_id = p_technician_id
                      else t.technician_id = v_ctx.actor_employee_id or t.technician_id is null
                  end
              )
          )
          and (
              v_search is null
              or t.client_name ilike '%' || v_search || '%'
              or t.os_number ilike '%' || v_search || '%'
              or t.device_model ilike '%' || v_search || '%'
              or coalesce(t.serial_number, '') ilike '%' || v_search || '%'
              or coalesce(t.contact_info, '') ilike '%' || v_search || '%'
          )
    ), filtered as (
        select *
          from base b
         where p_cursor is null
            or (b.priority_rank, b.effective_sort_at, b.deadline_sort_at, b.created_at, b.id)
               > (v_cursor_priority, v_cursor_effective, v_cursor_deadline, v_cursor_created, v_cursor_id)
    ), page_plus_one as materialized (
        select *
          from filtered
         order by priority_rank, effective_sort_at, deadline_sort_at, created_at, id
         limit p_limit + 1
    ), page_rows as materialized (
        select *
          from page_plus_one
         order by priority_rank, effective_sort_at, deadline_sort_at, created_at, id
         limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(
                (to_jsonb(p) - 'priority_rank' - 'effective_sort_at' - 'deadline_sort_at')
                || jsonb_build_object('_card_summary', true)
                order by p.priority_rank, p.effective_sort_at, p.deadline_sort_at, p.created_at, p.id
            )
            from page_rows p
        ), '[]'::jsonb),
        'total', (select count(*) from base),
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (
            select jsonb_build_object(
                'priority_rank', p.priority_rank,
                'effective_at', p.effective_sort_at,
                'deadline_at', p.deadline_sort_at,
                'created_at', p.created_at,
                'id', p.id
            )
            from page_rows p
            order by p.priority_rank desc, p.effective_sort_at desc, p.deadline_sort_at desc, p.created_at desc, p.id desc
            limit 1
        )
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_ticket_cards_page(
    text, text, uuid, text, integer, jsonb,
    boolean, boolean, boolean, boolean, boolean
) from public;
grant execute on function public.get_ticket_cards_page(
    text, text, uuid, text, integer, jsonb,
    boolean, boolean, boolean, boolean, boolean
) to anon, authenticated;

comment on function public.get_ticket_cards_page(
    text, text, uuid, text, integer, jsonb,
    boolean, boolean, boolean, boolean, boolean
) is 'Returns one bounded, keyset-paginated OS card page. Workspace comes only from the current actor and ticket RLS remains active.';

commit;
