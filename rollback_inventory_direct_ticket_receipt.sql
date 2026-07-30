begin;

create or replace function public.get_inventory_purchase_detail(p_purchase_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_ctx record; v_purchase public.inventory_purchases%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');
    select * into v_purchase from public.inventory_purchases p
    where p.workspace_id = v_ctx.workspace_id and p.id = p_purchase_id;
    if not found then raise exception 'Compra nao encontrada.'; end if;
    return jsonb_build_object(
        'purchase', to_jsonb(v_purchase),
        'items', coalesce((
            select jsonb_agg(jsonb_build_object(
                'purchase_item_id', pi.id,
                'item_id', pi.item_id,
                'item_name', pi.item_name_snapshot,
                'ordered_quantity', pi.ordered_quantity,
                'received_quantity', pi.received_quantity,
                'pending_quantity', pi.ordered_quantity - pi.received_quantity,
                'unit_cost', pi.unit_cost,
                'supplier_sku', pi.supplier_sku_snapshot
            ) order by pi.created_at, pi.id)
            from public.inventory_purchase_items pi
            where pi.workspace_id = v_ctx.workspace_id and pi.purchase_id = p_purchase_id
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public.get_inventory_purchase_detail(uuid) from public;
grant execute on function public.get_inventory_purchase_detail(uuid) to anon, authenticated;

create or replace function public.receive_inventory_purchase(
    p_purchase_id uuid,
    p_receipts jsonb,
    p_confirm_allocation boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_purchase public.inventory_purchases%rowtype;
    v_receipt jsonb;
    v_purchase_item public.inventory_purchase_items%rowtype;
    v_item public.inventory_items%rowtype;
    v_quantity numeric(14,3);
    v_unit_cost numeric(14,4);
    v_location_id uuid;
    v_total_physical numeric(14,3);
    v_old_average numeric(14,4);
    v_new_average numeric(14,4);
    v_ticket_id uuid;
    v_allocation_result jsonb;
    v_ready_result jsonb;
    v_ready_tickets jsonb := '[]'::jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    if p_receipts is null or jsonb_typeof(p_receipts) <> 'array'
       or jsonb_array_length(p_receipts) < 1
       or jsonb_array_length(p_receipts) > 100 then
        raise exception 'Informe os itens recebidos.';
    end if;

    select * into v_purchase
    from public.inventory_purchases p
    where p.id = p_purchase_id
      and p.workspace_id = v_ctx.workspace_id
      and p.status in ('ordered', 'partial')
    for update;
    if not found then raise exception 'Compra nao encontrada ou ja encerrada.'; end if;

    for v_receipt in select value from jsonb_array_elements(p_receipts)
    loop
        begin
            v_quantity := (v_receipt ->> 'quantity')::numeric;
            v_unit_cost := (v_receipt ->> 'unit_cost')::numeric;
            v_location_id := (v_receipt ->> 'location_id')::uuid;
            select * into v_purchase_item
            from public.inventory_purchase_items pi
            where pi.id = (v_receipt ->> 'purchase_item_id')::uuid
              and pi.workspace_id = v_ctx.workspace_id
              and pi.purchase_id = p_purchase_id
            for update;
        exception when others then
            raise exception 'Recebimento invalido.';
        end;
        if not found then raise exception 'Item da compra nao encontrado.'; end if;
        if v_quantity is null or v_quantity <= 0
           or v_purchase_item.received_quantity + v_quantity > v_purchase_item.ordered_quantity then
            raise exception 'Quantidade recebida invalida para %.',
                v_purchase_item.item_name_snapshot;
        end if;
        if v_unit_cost is null or v_unit_cost < 0 then
            raise exception 'Informe o custo unitario de %.',
                v_purchase_item.item_name_snapshot;
        end if;
        if not exists (
            select 1 from public.inventory_locations l
            where l.id = v_location_id
              and l.workspace_id = v_ctx.workspace_id
              and l.active
        ) then
            raise exception 'Localizacao de recebimento invalida.';
        end if;

        select * into v_item
        from public.inventory_items i
        where i.id = v_purchase_item.item_id
          and i.workspace_id = v_ctx.workspace_id
        for update;
        if not v_item.allow_decimal and v_quantity <> trunc(v_quantity) then
            raise exception '% aceita apenas quantidades inteiras.', v_item.name;
        end if;

        select coalesce(sum(b.physical_quantity), 0)
        into v_total_physical
        from public.inventory_balances b
        where b.workspace_id = v_ctx.workspace_id
          and b.item_id = v_item.id;

        select coalesce(c.average_cost, 0)
        into v_old_average
        from public.inventory_item_costs c
        where c.workspace_id = v_ctx.workspace_id and c.item_id = v_item.id
        for update;

        insert into public.inventory_balances(
            workspace_id, item_id, location_id, physical_quantity, reserved_quantity
        ) values (
            v_ctx.workspace_id, v_item.id, v_location_id, 0, 0
        )
        on conflict (workspace_id, item_id, location_id) do nothing;

        perform 1
        from public.inventory_balances b
        where b.workspace_id = v_ctx.workspace_id
          and b.item_id = v_item.id
          and b.location_id = v_location_id
        for update;

        update public.inventory_balances
        set physical_quantity = physical_quantity + v_quantity,
            updated_at = now()
        where workspace_id = v_ctx.workspace_id
          and item_id = v_item.id
          and location_id = v_location_id;

        v_new_average := case
            when v_total_physical + v_quantity <= 0 then v_unit_cost
            else (
                (v_total_physical * v_old_average) + (v_quantity * v_unit_cost)
            ) / (v_total_physical + v_quantity)
        end;

        update public.inventory_item_costs
        set average_cost = v_new_average,
            last_cost = v_unit_cost,
            updated_at = now()
        where workspace_id = v_ctx.workspace_id and item_id = v_item.id;

        update public.inventory_purchase_items
        set received_quantity = received_quantity + v_quantity,
            unit_cost = v_unit_cost,
            updated_at = now()
        where id = v_purchase_item.id and workspace_id = v_ctx.workspace_id;

        insert into public.inventory_movements(
            workspace_id, item_id, location_id, movement_type,
            physical_delta, reserved_delta, unit_cost_snapshot,
            purchase_id, reason,
            actor_user_id, actor_employee_id, actor_name
        ) values (
            v_ctx.workspace_id, v_item.id, v_location_id,
            'purchase_receipt', v_quantity, 0, v_unit_cost,
            p_purchase_id, 'Recebimento de compra',
            v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
        );
    end loop;

    update public.inventory_purchases p
    set status = case
            when not exists (
                select 1 from public.inventory_purchase_items pi
                where pi.workspace_id = p.workspace_id
                  and pi.purchase_id = p.id
                  and pi.received_quantity < pi.ordered_quantity
            ) then 'received'
            else 'partial'
        end,
        completed_at = case
            when not exists (
                select 1 from public.inventory_purchase_items pi
                where pi.workspace_id = p.workspace_id
                  and pi.purchase_id = p.id
                  and pi.received_quantity < pi.ordered_quantity
            ) then now()
            else null
        end,
        updated_at = now()
    where p.id = p_purchase_id and p.workspace_id = v_ctx.workspace_id
    returning * into v_purchase;

    if p_confirm_allocation then
        for v_ticket_id in
            select tp.ticket_id
            from public.inventory_purchase_items pi
            join public.inventory_purchase_allocations a
              on a.workspace_id = pi.workspace_id and a.purchase_item_id = pi.id
            join public.ticket_part_items tp
              on tp.workspace_id = a.workspace_id and tp.id = a.ticket_part_item_id
            join public.tickets t
              on t.workspace_id = tp.workspace_id and t.id = tp.ticket_id
            where pi.workspace_id = v_ctx.workspace_id
              and pi.purchase_id = p_purchase_id
            group by tp.ticket_id
            order by bool_or(coalesce(t.priority_requested, false)) desc,
                     min(tp.created_at), tp.ticket_id
        loop
            v_allocation_result := private.inventory_allocate_ticket_parts(
                v_ctx.workspace_id, v_ticket_id
            );
            if coalesce((v_allocation_result ->> 'fully_reserved')::boolean, false) then
                v_ready_result := private.inventory_resume_ready_ticket(
                    v_ctx.workspace_id, v_ticket_id
                );
                v_ready_tickets := v_ready_tickets || jsonb_build_array(
                    jsonb_build_object(
                        'ticket_id', v_ticket_id,
                        'resumed', coalesce((v_ready_result ->> 'resumed')::boolean, false)
                    )
                );
            end if;
        end loop;
    end if;

    return jsonb_build_object(
        'success', true,
        'purchase_id', p_purchase_id,
        'status', v_purchase.status,
        'ready_tickets', v_ready_tickets,
        'allocation_confirmed', coalesce(p_confirm_allocation, false)
    );
end;
$$;

revoke all on function public.receive_inventory_purchase(uuid, jsonb, boolean)
from public;
grant execute on function public.receive_inventory_purchase(uuid, jsonb, boolean)
to anon, authenticated;

create or replace function private.inventory_sync_purchase_fulfillment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.inventory_purchase_allocations a
    set fulfilled_quantity = least(a.allocated_quantity, new.received_quantity),
        updated_at = now()
    where a.workspace_id = new.workspace_id and a.purchase_item_id = new.id;
    update public.inventory_items i
    set last_purchase_at = now(), updated_at = now()
    where i.workspace_id = new.workspace_id and i.id = new.item_id
      and new.received_quantity > old.received_quantity;
    return new;
end;
$$;

revoke all on function private.inventory_sync_purchase_fulfillment()
from public, anon, authenticated;

drop function if exists private.inventory_get_direct_ticket_location(uuid);

commit;
