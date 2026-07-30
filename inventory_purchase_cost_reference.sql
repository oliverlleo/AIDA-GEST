-- Registra o custo previsto na compra e fornece uma referência interna
-- para a formação do orçamento da OS.

begin;

create index if not exists inventory_purchase_items_item_cost_history_idx
    on public.inventory_purchase_items(workspace_id, item_id, created_at desc, id desc)
    include (unit_cost, received_quantity, purchase_id)
    where unit_cost is not null;

create or replace function public.get_inventory_purchase_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    return jsonb_build_object(
        'pending_parts', coalesce((
            select jsonb_agg(jsonb_build_object(
                'ticket_part_item_id', tp.id,
                'ticket_id', tp.ticket_id,
                'os_number', t.os_number,
                'client_name', t.client_name,
                'item_id', tp.requested_item_id,
                'item_name', tp.requested_name_snapshot,
                'requested_quantity', tp.requested_quantity,
                'reserved_quantity', coalesce(r.reserved_quantity, 0),
                'already_ordered_quantity', coalesce(a.ordered_quantity, 0),
                'missing_quantity', greatest(0, tp.requested_quantity
                    - coalesce(r.reserved_quantity, 0)
                    - coalesce(a.ordered_quantity, 0)),
                'last_cost', case when coalesce(c.has_cost_history, false) then c.last_cost end,
                'average_cost', case when coalesce(c.has_cost_history, false) then c.average_cost end,
                'has_cost_history', coalesce(c.has_cost_history, false),
                'priority_requested', coalesce(t.priority_requested, false),
                'created_at', tp.created_at
            ) order by coalesce(t.priority_requested, false) desc, tp.created_at, tp.id)
            from public.ticket_part_items tp
            join public.tickets t
              on t.workspace_id = tp.workspace_id and t.id = tp.ticket_id
            left join lateral (
                select sum(ir.reserved_quantity - ir.consumed_quantity - ir.released_quantity) reserved_quantity
                from public.inventory_reservations ir
                where ir.workspace_id = tp.workspace_id
                  and ir.ticket_part_item_id = tp.id and ir.status = 'active'
            ) r on true
            left join lateral (
                select sum(ipa.allocated_quantity - ipa.fulfilled_quantity) ordered_quantity
                from public.inventory_purchase_allocations ipa
                join public.inventory_purchase_items ipi
                  on ipi.workspace_id = ipa.workspace_id and ipi.id = ipa.purchase_item_id
                join public.inventory_purchases ip
                  on ip.workspace_id = ipi.workspace_id and ip.id = ipi.purchase_id
                where ipa.workspace_id = tp.workspace_id
                  and ipa.ticket_part_item_id = tp.id
                  and ip.status in ('draft', 'ordered', 'partial')
            ) a on true
            left join lateral (
                select coalesce(lp.unit_cost, case
                           when ic.last_cost > 0 then ic.last_cost
                           when ic.average_cost > 0 then ic.average_cost
                       end) last_cost,
                       ic.average_cost,
                       (
                           lp.unit_cost is not null
                           or ic.last_cost > 0
                           or ic.average_cost > 0
                       ) has_cost_history
                from (select 1) seed
                left join public.inventory_item_costs ic
                  on ic.workspace_id = tp.workspace_id
                 and ic.item_id = tp.requested_item_id
                left join lateral (
                    select pi.unit_cost
                    from public.inventory_purchase_items pi
                    join public.inventory_purchases p
                      on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id
                    where pi.workspace_id = tp.workspace_id
                      and pi.item_id = tp.requested_item_id
                      and pi.unit_cost is not null
                      and p.status <> 'cancelled'
                    order by p.created_at desc, pi.created_at desc, pi.id desc
                    limit 1
                ) lp on true
            ) c on true
            where tp.workspace_id = v_ctx.workspace_id
              and tp.status in ('partial', 'purchase_pending')
              and greatest(0, tp.requested_quantity
                    - coalesce(r.reserved_quantity, 0)
                    - coalesce(a.ordered_quantity, 0)) > 0
        ), '[]'::jsonb),
        'purchases', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', p.id,
                'supplier_id', p.supplier_id,
                'supplier_name', p.supplier_name_snapshot,
                'status', p.status,
                'urgent', p.urgent,
                'notes', p.notes,
                'ordered_at', p.ordered_at,
                'created_at', p.created_at,
                'item_count', x.item_count,
                'ordered_quantity', x.ordered_quantity,
                'received_quantity', x.received_quantity,
                'estimated_total', x.estimated_total,
                'ticket_ids', x.ticket_ids
            ) order by p.urgent desc, p.created_at, p.id)
            from public.inventory_purchases p
            join lateral (
                select count(*) item_count,
                       sum(pi.ordered_quantity) ordered_quantity,
                       sum(pi.received_quantity) received_quantity,
                       sum(pi.ordered_quantity * coalesce(pi.unit_cost, 0)) estimated_total,
                       coalesce((
                           select jsonb_agg(distinct tp.ticket_id)
                           from public.inventory_purchase_items pi2
                           join public.inventory_purchase_allocations a
                             on a.workspace_id = pi2.workspace_id and a.purchase_item_id = pi2.id
                           join public.ticket_part_items tp
                             on tp.workspace_id = a.workspace_id and tp.id = a.ticket_part_item_id
                           where pi2.workspace_id = p.workspace_id and pi2.purchase_id = p.id
                       ), '[]'::jsonb) ticket_ids
                from public.inventory_purchase_items pi
                where pi.workspace_id = p.workspace_id and pi.purchase_id = p.id
            ) x on true
            where p.workspace_id = v_ctx.workspace_id
              and p.status in ('draft', 'ordered', 'partial')
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public.get_inventory_purchase_queue() from public;
grant execute on function public.get_inventory_purchase_queue() to anon, authenticated;

create or replace function public.create_inventory_purchase(
    p_supplier_id uuid,
    p_allocations jsonb,
    p_urgent boolean default false,
    p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_supplier public.fornecedores%rowtype;
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

    if p_allocations is null or jsonb_typeof(p_allocations) <> 'array'
       or jsonb_array_length(p_allocations) < 1
       or jsonb_array_length(p_allocations) > 100 then
        raise exception 'Informe entre 1 e 100 itens para compra.';
    end if;

    select * into v_supplier
    from public.fornecedores f
    where f.id = p_supplier_id and f.workspace_id = v_ctx.workspace_id;
    if not found then raise exception 'Fornecedor nao encontrado.'; end if;

    -- Valida todas as entradas antes de criar o cabeçalho da compra.
    for v_allocation in select value from jsonb_array_elements(p_allocations)
    loop
        begin
            v_quantity := (v_allocation ->> 'quantity')::numeric;
            v_unit_cost := (v_allocation ->> 'unit_cost')::numeric;
        exception when others then
            raise exception 'Quantidade ou custo unitario invalido.';
        end;
        if v_quantity is null or v_quantity <= 0 then
            raise exception 'Informe uma quantidade maior que zero.';
        end if;
        if v_unit_cost is null or v_unit_cost < 0 or v_unit_cost > 9999999999.9999 then
            raise exception 'Informe um custo unitario valido para cada peca.';
        end if;
    end loop;

    insert into public.inventory_purchases(
        workspace_id, supplier_id, supplier_name_snapshot, status,
        urgent, notes, ordered_at,
        created_by_user_id, created_by_employee_id, created_by_name
    ) values (
        v_ctx.workspace_id, v_supplier.id, v_supplier.razao_social,
        'ordered', coalesce(p_urgent, false), nullif(btrim(p_notes), ''), now(),
        v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
    ) returning id into v_purchase_id;

    for v_allocation in select value from jsonb_array_elements(p_allocations)
    loop
        begin
            v_quantity := (v_allocation ->> 'quantity')::numeric;
            v_unit_cost := (v_allocation ->> 'unit_cost')::numeric;
            select * into v_part
            from public.ticket_part_items tp
            where tp.id = (v_allocation ->> 'ticket_part_item_id')::uuid
              and tp.workspace_id = v_ctx.workspace_id
              and tp.status in ('partial', 'purchase_pending')
            for update;
        exception when invalid_text_representation or numeric_value_out_of_range then
            raise exception 'Item pendente, quantidade ou custo invalido.';
        end;
        if not found then raise exception 'Solicitacao de peca pendente nao encontrada.'; end if;

        select coalesce(sum(
            r.reserved_quantity - r.consumed_quantity - r.released_quantity
        ), 0)
        into v_reserved
        from public.inventory_reservations r
        where r.workspace_id = v_ctx.workspace_id
          and r.ticket_part_item_id = v_part.id
          and r.status = 'active';

        select coalesce(sum(
            a.allocated_quantity - a.fulfilled_quantity
        ), 0)
        into v_already_ordered
        from public.inventory_purchase_allocations a
        join public.inventory_purchase_items pi
          on pi.workspace_id = a.workspace_id and pi.id = a.purchase_item_id
        join public.inventory_purchases p
          on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id
        where a.workspace_id = v_ctx.workspace_id
          and a.ticket_part_item_id = v_part.id
          and p.status in ('draft', 'ordered', 'partial');

        v_missing := greatest(
            0,
            v_part.requested_quantity - v_reserved - v_already_ordered
        );
        if v_quantity > v_missing then
            raise exception 'A quantidade de % excede a falta atual de %.',
                v_part.requested_name_snapshot, v_missing;
        end if;

        insert into public.inventory_purchase_items(
            workspace_id, purchase_id, item_id, item_name_snapshot,
            ordered_quantity, supplier_sku_snapshot, unit_cost
        ) values (
            v_ctx.workspace_id, v_purchase_id, v_part.requested_item_id,
            v_part.requested_name_snapshot, v_quantity,
            (select s.supplier_sku from public.inventory_item_suppliers s
             where s.workspace_id = v_ctx.workspace_id
               and s.item_id = v_part.requested_item_id
               and s.supplier_id = v_supplier.id),
            v_unit_cost
        ) returning id into v_purchase_item_id;

        insert into public.inventory_purchase_allocations(
            workspace_id, purchase_item_id, ticket_part_item_id,
            allocated_quantity
        ) values (
            v_ctx.workspace_id, v_purchase_item_id, v_part.id, v_quantity
        );

        if not (v_part.ticket_id = any(v_ticket_ids)) then
            v_ticket_ids := array_append(v_ticket_ids, v_part.ticket_id);
        end if;
    end loop;

    foreach v_ticket_id in array v_ticket_ids
    loop
        update public.tickets t
        set parts_status = 'Comprado',
            parts_purchased_at = coalesce(parts_purchased_at, now()),
            supplier_purchases = coalesce(t.supplier_purchases, '[]'::jsonb)
                || jsonb_build_array(jsonb_build_object(
                    'inventory_purchase_id', v_purchase_id,
                    'supplier_id', v_supplier.id,
                    'supplier_name', v_supplier.razao_social,
                    'purchased_at', now(),
                    'purchased_by', coalesce(
                        v_ctx.actor_employee_id::text,
                        v_ctx.actor_user_id::text
                    ),
                    'structured_inventory', true
                )),
            updated_at = now()
        where t.workspace_id = v_ctx.workspace_id and t.id = v_ticket_id;

        insert into public.ticket_logs(ticket_id, action, details, user_name)
        values (
            v_ticket_id,
            'Confirmou Compra',
            format(
                '**%s** registrou a compra das pecas pendentes no fornecedor **%s** para a **OS %s**.',
                v_ctx.actor_name,
                v_supplier.razao_social,
                coalesce((
                    select t.os_number from public.tickets t
                    where t.workspace_id = v_ctx.workspace_id and t.id = v_ticket_id
                ), 'nao informada')
            ),
            v_ctx.actor_name
        );
    end loop;

    return jsonb_build_object(
        'success', true,
        'purchase_id', v_purchase_id,
        'ticket_ids', to_jsonb(v_ticket_ids)
    );
end;
$$;

revoke all on function public.create_inventory_purchase(uuid, jsonb, boolean, text)
from public;
grant execute on function public.create_inventory_purchase(uuid, jsonb, boolean, text)
to anon, authenticated;

create or replace function public.get_ticket_inventory_budget_cost_summaries(
    p_ticket_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    if p_ticket_ids is null or cardinality(p_ticket_ids) = 0 then
        return '[]'::jsonb;
    end if;
    if cardinality(p_ticket_ids) > 100 then
        raise exception 'No maximo 100 OS podem ser consultadas por vez.';
    end if;

    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', t.id,
            'inventory_cost_summary', jsonb_build_object(
                'total', coalesce(x.total, 0),
                'item_count', coalesce(x.item_count, 0),
                'priced_item_count', coalesce(x.priced_item_count, 0),
                'missing_cost_count', coalesce(x.item_count, 0) - coalesce(x.priced_item_count, 0)
            )
        ) order by t.id)
        from public.tickets t
        left join lateral (
            select count(*) item_count,
                   count(*) filter (where ref.unit_cost is not null) priced_item_count,
                   sum(tp.requested_quantity * coalesce(ref.unit_cost, 0)) total
            from public.ticket_part_items tp
            left join lateral (
                select coalesce(cp.unit_cost, hc.unit_cost) unit_cost
                from (select 1) seed
                left join lateral (
                    select pi.unit_cost
                    from public.inventory_purchase_allocations pa
                    join public.inventory_purchase_items pi
                      on pi.workspace_id = pa.workspace_id and pi.id = pa.purchase_item_id
                    join public.inventory_purchases p
                      on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id
                    where pa.workspace_id = tp.workspace_id
                      and pa.ticket_part_item_id = tp.id
                      and p.status <> 'cancelled'
                      and pi.unit_cost is not null
                    order by p.created_at desc, pi.created_at desc, pi.id desc
                    limit 1
                ) cp on true
                left join lateral (
                    select coalesce(lp.unit_cost, case
                               when ic.last_cost > 0 then ic.last_cost
                               when ic.average_cost > 0 then ic.average_cost
                           end) unit_cost
                    from (select 1) seed
                    left join public.inventory_item_costs ic
                      on ic.workspace_id = tp.workspace_id
                     and ic.item_id = tp.requested_item_id
                    left join lateral (
                        select pi.unit_cost
                        from public.inventory_purchase_items pi
                        join public.inventory_purchases p
                          on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id
                        where pi.workspace_id = tp.workspace_id
                          and pi.item_id = tp.requested_item_id
                          and pi.unit_cost is not null
                          and p.status <> 'cancelled'
                        order by p.created_at desc, pi.created_at desc, pi.id desc
                        limit 1
                    ) lp on true
                ) hc on true
            ) ref on true
            where tp.workspace_id = t.workspace_id
              and tp.ticket_id = t.id
              and tp.status <> 'cancelled'
        ) x on true
        where t.workspace_id = v_ctx.workspace_id
          and t.id = any(p_ticket_ids)
          and t.deleted_at is null
    ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_ticket_inventory_budget_cost_summaries(uuid[])
from public;
grant execute on function public.get_ticket_inventory_budget_cost_summaries(uuid[])
to anon, authenticated;

create or replace function public.get_ticket_inventory_budget_costs(p_ticket_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_items jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    if not exists (
        select 1
        from public.tickets t
        where t.workspace_id = v_ctx.workspace_id
          and t.id = p_ticket_id
          and t.deleted_at is null
    ) then
        raise exception 'OS nao encontrada.';
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
        'ticket_part_item_id', q.ticket_part_item_id,
        'item_name', q.item_name,
        'quantity', q.quantity,
        'unit_cost', q.unit_cost,
        'subtotal', q.quantity * coalesce(q.unit_cost, 0),
        'source', q.source
    ) order by q.created_at, q.ticket_part_item_id), '[]'::jsonb)
    into v_items
    from (
        select tp.id ticket_part_item_id,
               tp.requested_name_snapshot item_name,
               tp.requested_quantity quantity,
               coalesce(cp.unit_cost, hc.unit_cost) unit_cost,
               case
                   when cp.unit_cost is not null then 'current_purchase'
                   when hc.unit_cost is not null then hc.source
                   else 'missing'
               end source,
               tp.created_at
        from public.ticket_part_items tp
        left join lateral (
            select pi.unit_cost
            from public.inventory_purchase_allocations pa
            join public.inventory_purchase_items pi
              on pi.workspace_id = pa.workspace_id and pi.id = pa.purchase_item_id
            join public.inventory_purchases p
              on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id
            where pa.workspace_id = tp.workspace_id
              and pa.ticket_part_item_id = tp.id
              and p.status <> 'cancelled'
              and pi.unit_cost is not null
            order by p.created_at desc, pi.created_at desc, pi.id desc
            limit 1
        ) cp on true
        left join lateral (
            select coalesce(lp.unit_cost, case
                       when ic.last_cost > 0 then ic.last_cost
                       when ic.average_cost > 0 then ic.average_cost
                   end) unit_cost,
                   case
                       when lp.unit_cost is not null then 'last_purchase'
                       when ic.last_cost > 0 or ic.average_cost > 0 then 'last_cost'
                       else 'missing'
                   end source
            from (select 1) seed
            left join public.inventory_item_costs ic
              on ic.workspace_id = tp.workspace_id
             and ic.item_id = tp.requested_item_id
            left join lateral (
                select pi.unit_cost
                from public.inventory_purchase_items pi
                join public.inventory_purchases p
                  on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id
                where pi.workspace_id = tp.workspace_id
                  and pi.item_id = tp.requested_item_id
                  and pi.unit_cost is not null
                  and p.status <> 'cancelled'
                order by p.created_at desc, pi.created_at desc, pi.id desc
                limit 1
            ) lp on true
        ) hc on true
        where tp.workspace_id = v_ctx.workspace_id
          and tp.ticket_id = p_ticket_id
          and tp.status <> 'cancelled'
    ) q;

    return jsonb_build_object(
        'ticket_id', p_ticket_id,
        'items', v_items,
        'total', coalesce((
            select sum(
                coalesce((item ->> 'subtotal')::numeric, 0)
            )
            from jsonb_array_elements(v_items) item
        ), 0),
        'missing_cost_count', coalesce((
            select count(*)
            from jsonb_array_elements(v_items) item
            where item ->> 'source' = 'missing'
        ), 0)
    );
end;
$$;

revoke all on function public.get_ticket_inventory_budget_costs(uuid) from public;
grant execute on function public.get_ticket_inventory_budget_costs(uuid)
to anon, authenticated;

commit;
