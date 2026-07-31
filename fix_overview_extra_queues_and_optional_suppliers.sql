-- Visão Geral: filas de teste/agendamento e fornecedor manual opcional.
-- As funções derivam o workspace pelo ator autenticado e não recebem tenant do navegador.

begin;

create index if not exists tickets_overview_extra_queue_idx
    on public.tickets (
        workspace_id,
        status,
        priority_requested desc,
        deadline asc nulls last,
        overview_queue_entered_at asc nulls last,
        created_at asc,
        id
    )
    where deleted_at is null
      and status in ('Aberto', 'Analise Tecnica', 'Aprovacao', 'Andamento Reparo', 'Teste Final');

create or replace function public.get_overview_extra_queue_page(
    p_queue_key text,
    p_window text default 'all',
    p_basis text default 'auto',
    p_status text default null,
    p_technician_id uuid default null,
    p_search text default null,
    p_limit integer default 20,
    p_cursor jsonb default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_config jsonb := '{}'::jsonb;
    v_final_test boolean;
    v_analysis_appointments boolean;
    v_repair_appointments boolean;
    v_cursor_priority integer;
    v_cursor_due timestamptz;
    v_cursor_entered timestamptz;
    v_cursor_created timestamptz;
    v_cursor_id uuid;
    v_total bigint;
    v_items jsonb;
    v_has_more boolean;
    v_next_cursor jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_queue_key not in ('pendingTests', 'unscheduledTickets') then
        raise exception 'Fila da Visão Geral inválida.';
    end if;
    if p_window not in ('today', 'today_tomorrow', 'next_7_days', 'overdue', 'no_deadline', 'all') then
        raise exception 'Parâmetro p_window inválido.';
    end if;
    if p_basis not in ('auto', 'analysis', 'delivery', 'entry', 'outsourced') then
        raise exception 'Parâmetro p_basis inválido.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'Parâmetro p_limit deve estar entre 1 e 50.';
    end if;
    if p_cursor is not null then
        begin
            v_cursor_priority := (p_cursor ->> 'priority_rank')::integer;
            v_cursor_due := (p_cursor ->> 'due_sort')::timestamptz;
            v_cursor_entered := (p_cursor ->> 'entered_sort')::timestamptz;
            v_cursor_created := (p_cursor ->> 'created_at')::timestamptz;
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de paginação inválido.';
        end;
        if v_cursor_priority is null or v_cursor_due is null or v_cursor_entered is null
           or v_cursor_created is null or v_cursor_id is null then
            raise exception 'Cursor de paginação incompleto.';
        end if;
    end if;

    select coalesce(w.tracker_config, '{}'::jsonb)
      into v_config
      from public.workspaces w
     where w.id = v_ctx.workspace_id;

    v_final_test := public.aida_config_bool(v_config, 'workflow', 'final_test', true);
    v_analysis_appointments := public.aida_config_bool(v_config, 'modules', 'agenda', true)
        and public.aida_ticket_field_mode(v_config, 'analysis_schedule', false) <> 'disabled';
    v_repair_appointments := public.aida_config_bool(v_config, 'modules', 'agenda', true)
        and public.aida_ticket_field_mode(v_config, 'repair_schedule', false) <> 'disabled';

    with base as (
        select
            t.*,
            case
                when p_basis = 'analysis' then t.analysis_deadline
                when p_basis = 'delivery' then t.deadline
                when p_basis = 'entry' then t.entry_date
                when p_basis = 'outsourced' then t.outsourced_deadline
                else case
                    when t.status in ('Aberto', 'Analise Tecnica') then coalesce(t.analysis_deadline, t.deadline)
                    else coalesce(t.deadline, t.analysis_deadline, t.outsourced_deadline)
                end
            end as effective_due_at
        from public.tickets t
        where t.workspace_id = v_ctx.workspace_id
          and t.deleted_at is null
          and t.status <> 'Finalizado'
          and (p_status is null or p_status = 'all' or t.status = p_status)
          and (p_technician_id is null or t.technician_id = p_technician_id)
          and (
              nullif(btrim(coalesce(p_search, '')), '') is null
              or t.client_name ilike '%' || p_search || '%'
              or t.os_number ilike '%' || p_search || '%'
              or t.device_model ilike '%' || p_search || '%'
              or t.serial_number ilike '%' || p_search || '%'
          )
    ), windowed as (
        select *,
            case
                when effective_due_at is null then 'no_deadline'
                when effective_due_at < date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo' then 'overdue'
                when effective_due_at < (date_trunc('day', now() at time zone 'America/Sao_Paulo') + interval '1 day') at time zone 'America/Sao_Paulo' then 'today'
                when effective_due_at < (date_trunc('day', now() at time zone 'America/Sao_Paulo') + interval '2 day') at time zone 'America/Sao_Paulo' then 'tomorrow'
                when effective_due_at < (date_trunc('day', now() at time zone 'America/Sao_Paulo') + interval '8 day') at time zone 'America/Sao_Paulo' then 'next_7_days'
                else 'later'
            end as urgency_bucket
        from base
    ), candidates as (
        select w.*,
            case
                when v_final_test and w.status = 'Teste Final' then 'pendingTests'
                when (v_analysis_appointments and w.status in ('Aberto', 'Analise Tecnica') and w.analysis_scheduled_at is null)
                  or (v_repair_appointments and (
                        w.status = 'Andamento Reparo'
                        or (w.status = 'Aprovacao' and w.budget_status = 'Aprovado'
                            and nullif(btrim(coalesce(w.parts_needed, '')), '') is null)
                      ) and w.repair_scheduled_at is null)
                    then 'unscheduledTickets'
            end as queue_key,
            case
                when v_analysis_appointments and w.status in ('Aberto', 'Analise Tecnica') and w.analysis_scheduled_at is null then 'analysis'
                when v_repair_appointments and (
                    w.status = 'Andamento Reparo'
                    or (w.status = 'Aprovacao' and w.budget_status = 'Aprovado'
                        and nullif(btrim(coalesce(w.parts_needed, '')), '') is null)
                ) and w.repair_scheduled_at is null then 'repair'
            end as unscheduled_type
        from windowed w
        where p_window = 'all'
           or (p_window = 'overdue' and w.urgency_bucket = 'overdue')
           or (p_window = 'no_deadline' and w.urgency_bucket = 'no_deadline')
           or (p_window = 'today' and w.urgency_bucket = 'today')
           or (p_window = 'today_tomorrow' and w.urgency_bucket in ('today', 'tomorrow'))
           or (p_window = 'next_7_days' and w.urgency_bucket in ('today', 'tomorrow', 'next_7_days'))
    ), ordered as (
        select c.*,
            case
                when coalesce(c.priority_requested, false) then 0
                when c.priority = 'Urgente' then 1
                when c.priority = 'Alta' then 2
                when c.priority = 'Normal' then 3
                when c.priority = 'Baixa' then 4
                else 5
            end as priority_rank,
            coalesce(c.effective_due_at, 'infinity'::timestamptz) as due_sort,
            coalesce(c.overview_queue_entered_at, c.updated_at, c.created_at, c.entry_date, 'infinity'::timestamptz) as entered_sort
        from candidates c
        where c.queue_key = p_queue_key
    ), after_cursor as (
        select * from ordered o
        where p_cursor is null
           or (o.priority_rank, o.due_sort, o.entered_sort, o.created_at, o.id)
              > (v_cursor_priority, v_cursor_due, v_cursor_entered, v_cursor_created, v_cursor_id)
    ), page_plus_one as materialized (
        select * from after_cursor
        order by priority_rank, due_sort, entered_sort, created_at, id
        limit p_limit + 1
    ), page_rows as materialized (
        select * from page_plus_one
        order by priority_rank, due_sort, entered_sort, created_at, id
        limit p_limit
    )
    select
        (select count(*) from ordered),
        coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'id', pr.id,
                    'os_number', pr.os_number,
                    'client_name', pr.client_name,
                    'device_model', pr.device_model,
                    'status', pr.status,
                    'technician_id', pr.technician_id,
                    'entry_date', pr.entry_date,
                    'created_at', pr.created_at,
                    'updated_at', pr.updated_at,
                    'priority', pr.priority,
                    'priority_requested', pr.priority_requested,
                    'deadline', pr.deadline,
                    'analysis_deadline', pr.analysis_deadline,
                    'effective_due_at', pr.effective_due_at,
                    'overview_queue_entered_at', pr.overview_queue_entered_at,
                    'unscheduled_type', pr.unscheduled_type
                )
                order by pr.priority_rank, pr.due_sort, pr.entered_sort, pr.created_at, pr.id
            ) from page_rows pr
        ), '[]'::jsonb),
        (select count(*) > p_limit from page_plus_one),
        (
            select jsonb_build_object(
                'priority_rank', pr.priority_rank,
                'due_sort', pr.due_sort,
                'entered_sort', pr.entered_sort,
                'created_at', pr.created_at,
                'id', pr.id
            ) from page_rows pr
            order by pr.priority_rank desc, pr.due_sort desc, pr.entered_sort desc, pr.created_at desc, pr.id desc
            limit 1
        )
    into v_total, v_items, v_has_more, v_next_cursor;

    return jsonb_build_object(
        'total', coalesce(v_total, 0),
        'items', coalesce(v_items, '[]'::jsonb),
        'has_more', coalesce(v_has_more, false),
        'next_cursor', v_next_cursor
    );
end;
$$;

revoke all on function public.get_overview_extra_queue_page(text, text, text, text, uuid, text, integer, jsonb) from public;
grant execute on function public.get_overview_extra_queue_page(text, text, text, text, uuid, text, integer, jsonb) to anon, authenticated;

create or replace function public.get_overview_extra_queues(
    p_window text,
    p_basis text,
    p_status text default null,
    p_technician_id uuid default null,
    p_search text default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
    select jsonb_build_object(
        'pendingTests', public.get_overview_extra_queue_page('pendingTests', p_window, p_basis, p_status, p_technician_id, p_search, 5, null),
        'unscheduledTickets', public.get_overview_extra_queue_page('unscheduledTickets', p_window, p_basis, p_status, p_technician_id, p_search, 5, null)
    );
$$;

revoke all on function public.get_overview_extra_queues(text, text, text, uuid, text) from public;
grant execute on function public.get_overview_extra_queues(text, text, text, uuid, text) to anon, authenticated;

alter table public.inventory_purchases
    alter column supplier_id drop not null;

drop function if exists public.create_inventory_purchase(uuid, jsonb, boolean, text);

create or replace function public.create_inventory_purchase(
    p_supplier_id uuid,
    p_allocations jsonb,
    p_urgent boolean default false,
    p_notes text default null,
    p_supplier_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_config jsonb := '{}'::jsonb;
    v_supplier_registry_enabled boolean;
    v_supplier public.fornecedores%rowtype;
    v_supplier_name text;
    v_supplier_id uuid;
    v_purchase_id uuid;
    v_allocation jsonb;
    v_part public.ticket_part_items%rowtype;
    v_purchase_item_id uuid;
    v_quantity numeric(14,3);
    v_unit_cost numeric(14,4);
    v_reserved numeric(14,3);
    v_already_ordered numeric(14,3);
    v_missing numeric(14,3);
    v_ticket_ids uuid[] := '{}'::uuid[];
    v_ticket_id uuid;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');
    select coalesce(w.tracker_config, '{}'::jsonb) into v_config from public.workspaces w where w.id = v_ctx.workspace_id;
    v_supplier_registry_enabled := public.aida_config_bool(v_config, 'modules', 'suppliers', true);

    if p_allocations is null or jsonb_typeof(p_allocations) <> 'array'
       or jsonb_array_length(p_allocations) < 1 or jsonb_array_length(p_allocations) > 100 then
        raise exception 'Informe entre 1 e 100 itens para compra.';
    end if;

    if v_supplier_registry_enabled then
        select * into v_supplier from public.fornecedores f
         where f.id = p_supplier_id and f.workspace_id = v_ctx.workspace_id;
        if not found then raise exception 'Selecione um fornecedor cadastrado.'; end if;
        v_supplier_id := v_supplier.id;
        v_supplier_name := v_supplier.razao_social;
    else
        v_supplier_name := nullif(btrim(coalesce(p_supplier_name, '')), '');
        if v_supplier_name is null or char_length(v_supplier_name) < 2 or char_length(v_supplier_name) > 160 then
            raise exception 'Informe o nome do fornecedor para a compra.';
        end if;
        v_supplier_id := null;
    end if;

    for v_allocation in select value from jsonb_array_elements(p_allocations) loop
        begin
            v_quantity := (v_allocation ->> 'quantity')::numeric;
            v_unit_cost := (v_allocation ->> 'unit_cost')::numeric;
        exception when others then
            raise exception 'Quantidade ou custo unitario invalido.';
        end;
        if v_quantity is null or v_quantity <= 0 then raise exception 'Informe uma quantidade maior que zero.'; end if;
        if v_unit_cost is null or v_unit_cost < 0 or v_unit_cost > 9999999999.9999 then raise exception 'Informe um custo unitario valido para cada peca.'; end if;
    end loop;

    insert into public.inventory_purchases(workspace_id, supplier_id, supplier_name_snapshot, status, urgent, notes, ordered_at, created_by_user_id, created_by_employee_id, created_by_name)
    values (v_ctx.workspace_id, v_supplier_id, v_supplier_name, 'ordered', coalesce(p_urgent, false), nullif(btrim(p_notes), ''), now(), v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name)
    returning id into v_purchase_id;

    for v_allocation in select value from jsonb_array_elements(p_allocations) loop
        begin
            v_quantity := (v_allocation ->> 'quantity')::numeric;
            v_unit_cost := (v_allocation ->> 'unit_cost')::numeric;
            select * into v_part from public.ticket_part_items tp
             where tp.id = (v_allocation ->> 'ticket_part_item_id')::uuid
               and tp.workspace_id = v_ctx.workspace_id and tp.status in ('partial', 'purchase_pending') for update;
        exception when invalid_text_representation or numeric_value_out_of_range then
            raise exception 'Item pendente, quantidade ou custo invalido.';
        end;
        if not found then raise exception 'Solicitacao de peca pendente nao encontrada.'; end if;
        select coalesce(sum(r.reserved_quantity - r.consumed_quantity - r.released_quantity), 0) into v_reserved from public.inventory_reservations r where r.workspace_id = v_ctx.workspace_id and r.ticket_part_item_id = v_part.id and r.status = 'active';
        select coalesce(sum(a.allocated_quantity - a.fulfilled_quantity), 0) into v_already_ordered from public.inventory_purchase_allocations a join public.inventory_purchase_items pi on pi.workspace_id = a.workspace_id and pi.id = a.purchase_item_id join public.inventory_purchases p on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id where a.workspace_id = v_ctx.workspace_id and a.ticket_part_item_id = v_part.id and p.status in ('draft', 'ordered', 'partial');
        v_missing := greatest(0, v_part.requested_quantity - v_reserved - v_already_ordered);
        if v_quantity > v_missing then raise exception 'A quantidade de % excede a falta atual de %.', v_part.requested_name_snapshot, v_missing; end if;
        insert into public.inventory_purchase_items(workspace_id, purchase_id, item_id, item_name_snapshot, ordered_quantity, supplier_sku_snapshot, unit_cost)
        values (v_ctx.workspace_id, v_purchase_id, v_part.requested_item_id, v_part.requested_name_snapshot, v_quantity,
            case when v_supplier_id is null then null else (select s.supplier_sku from public.inventory_item_suppliers s where s.workspace_id = v_ctx.workspace_id and s.item_id = v_part.requested_item_id and s.supplier_id = v_supplier_id) end,
            v_unit_cost) returning id into v_purchase_item_id;
        insert into public.inventory_purchase_allocations(workspace_id, purchase_item_id, ticket_part_item_id, allocated_quantity) values (v_ctx.workspace_id, v_purchase_item_id, v_part.id, v_quantity);
        if not (v_part.ticket_id = any(v_ticket_ids)) then v_ticket_ids := array_append(v_ticket_ids, v_part.ticket_id); end if;
    end loop;

    foreach v_ticket_id in array v_ticket_ids loop
        update public.tickets t set parts_status = 'Comprado', parts_purchased_at = coalesce(parts_purchased_at, now()), supplier_purchases = coalesce(t.supplier_purchases, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('inventory_purchase_id', v_purchase_id, 'supplier_id', v_supplier_id, 'supplier_name', v_supplier_name, 'purchased_at', now(), 'purchased_by', coalesce(v_ctx.actor_employee_id::text, v_ctx.actor_user_id::text), 'structured_inventory', true)), updated_at = now() where t.workspace_id = v_ctx.workspace_id and t.id = v_ticket_id;
        insert into public.ticket_logs(ticket_id, action, details, user_name) values (v_ticket_id, 'Confirmou Compra', format('**%s** registrou a compra das pecas pendentes no fornecedor **%s** para a **OS %s**.', v_ctx.actor_name, v_supplier_name, coalesce((select t.os_number from public.tickets t where t.workspace_id = v_ctx.workspace_id and t.id = v_ticket_id), 'nao informada')), v_ctx.actor_name);
    end loop;
    return jsonb_build_object('success', true, 'purchase_id', v_purchase_id, 'ticket_ids', to_jsonb(v_ticket_ids));
end;
$$;

revoke all on function public.create_inventory_purchase(uuid, jsonb, boolean, text, text) from public;
-- Funcionários usam a chave anônima apenas como transporte, com x-employee-token
-- validado por get_current_actor_context e inventory_assert_access.
grant execute on function public.create_inventory_purchase(uuid, jsonb, boolean, text, text) to anon, authenticated;

commit;
