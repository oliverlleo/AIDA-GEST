-- Compras, recebimento parcial, alocacao e consumo final do estoque.
-- Depende de inventory_module_foundation.sql e inventory_workflow_integration.sql.

begin;

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
            select * into v_part
            from public.ticket_part_items tp
            where tp.id = (v_allocation ->> 'ticket_part_item_id')::uuid
              and tp.workspace_id = v_ctx.workspace_id
              and tp.status in ('partial', 'purchase_pending')
            for update;
        exception when others then
            raise exception 'Item pendente ou quantidade invalida.';
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
        if v_quantity is null or v_quantity <= 0 or v_quantity > v_missing then
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
            (select s.last_price from public.inventory_item_suppliers s
             where s.workspace_id = v_ctx.workspace_id
               and s.item_id = v_part.requested_item_id
               and s.supplier_id = v_supplier.id)
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
                '**%s** registrou a compra das peças pendentes no fornecedor **%s** para a **OS %s**.',
                v_ctx.actor_name,
                v_supplier.razao_social,
                coalesce((
                    select t.os_number from public.tickets t
                    where t.workspace_id = v_ctx.workspace_id and t.id = v_ticket_id
                ), 'não informada')
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

create or replace function private.inventory_resume_ready_ticket(
    p_workspace_id uuid,
    p_ticket_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_config jsonb;
    v_timer boolean;
    v_ready boolean;
begin
    select * into v_ctx from public.get_current_actor_context();
    select * into v_ticket
    from public.tickets t
    where t.workspace_id = p_workspace_id and t.id = p_ticket_id
    for update;
    if not found then return jsonb_build_object('ready', false); end if;

    select not exists (
        select 1 from public.ticket_part_items tp
        where tp.workspace_id = p_workspace_id
          and tp.ticket_id = p_ticket_id
          and tp.status in ('needed', 'pending_approval', 'partial', 'purchase_pending')
    )
    into v_ready;

    if not v_ready then
        return jsonb_build_object('ready', false, 'status', v_ticket.status);
    end if;

    update public.ticket_part_items
    set status = 'ready', updated_at = now()
    where workspace_id = p_workspace_id
      and ticket_id = p_ticket_id
      and status = 'reserved';

    select coalesce(w.tracker_config, '{}'::jsonb)
    into v_config from public.workspaces w where w.id = p_workspace_id;
    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);

    update public.tickets
    set status = 'Andamento Reparo',
        parts_status = 'Recebido',
        parts_received_at = now(),
        repair_paused_at = null,
        repair_start_at = case
            when v_ticket.repair_paused_at is not null then now()
            else repair_start_at
        end,
        repair_elapsed_seconds = case
            when v_timer then coalesce(repair_elapsed_seconds, 0)
            else 0
        end,
        repair_resume_count = case
            when v_ticket.repair_paused_at is not null
                then coalesce(repair_resume_count, 0) + 1
            else repair_resume_count
        end,
        updated_at = now()
    where workspace_id = p_workspace_id and id = p_ticket_id;

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        case when v_ticket.repair_paused_at is not null
            then 'Retomou Reparo após Compra'
            else 'Recebeu Peças'
        end,
        format(
            'Todas as peças da **OS %s** foram recebidas e reservadas. O reparo foi liberado por **%s**.%s',
            coalesce(v_ticket.os_number, 'não informada'),
            v_ctx.actor_name,
            case when v_ticket.repair_paused_at is not null and v_timer
                then format(
                    ' O cronômetro continuou dos **%s segundos** já acumulados.',
                    coalesce(v_ticket.repair_elapsed_seconds, 0)
                )
                else ''
            end
        ),
        v_ctx.actor_name
    );

    return jsonb_build_object(
        'ready', true,
        'status', 'Andamento Reparo',
        'resumed', v_ticket.repair_paused_at is not null
    );
end;
$$;

revoke all on function private.inventory_resume_ready_ticket(uuid, uuid)
from public, anon, authenticated;

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

create or replace function public.get_ticket_inventory_parts(p_ticket_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null;
    if not found then raise exception 'OS nao encontrada.'; end if;
    if v_ctx.is_technician
       and not v_ctx.is_admin
       and not v_ctx.is_attendant
       and v_ticket.technician_id is distinct from v_ctx.actor_employee_id then
        raise exception 'Tecnico so pode consultar as pecas da propria OS.';
    end if;

    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(jsonb_build_object(
                'ticket_part_item_id', tp.id,
                'requested_item_id', tp.requested_item_id,
                'original_item_id', tp.original_item_id,
                'substitution_type', tp.substitution_type,
                'name', tp.requested_name_snapshot,
                'requested_quantity', tp.requested_quantity,
                'request_stage', tp.request_stage,
                'status', tp.status,
                'reservations', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'reservation_id', r.id,
                        'item_id', r.item_id,
                        'item_name', i.name,
                        'location_id', r.location_id,
                        'location_name', l.name,
                        'reserved_quantity', r.reserved_quantity,
                        'remaining_quantity', r.reserved_quantity
                            - r.consumed_quantity - r.released_quantity,
                        'consumed_quantity', r.consumed_quantity,
                        'released_quantity', r.released_quantity,
                        'returned_quantity', r.returned_quantity,
                        'returnable_quantity', r.consumed_quantity - r.returned_quantity,
                        'status', r.status
                    ) order by l.normalized_address, r.id)
                    from public.inventory_reservations r
                    join public.inventory_items i
                      on i.workspace_id = r.workspace_id and i.id = r.item_id
                    join public.inventory_locations l
                      on l.workspace_id = r.workspace_id and l.id = r.location_id
                    where r.workspace_id = tp.workspace_id
                      and r.ticket_part_item_id = tp.id
                ), '[]'::jsonb)
            ) order by tp.created_at, tp.id)
            from public.ticket_part_items tp
            where tp.workspace_id = v_ctx.workspace_id
              and tp.ticket_id = p_ticket_id
              and tp.status <> 'cancelled'
        ), '[]'::jsonb)
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_ticket_inventory_parts(uuid) from public;
grant execute on function public.get_ticket_inventory_parts(uuid)
to anon, authenticated;

create or replace function public.complete_repair_with_inventory(
    p_ticket_id uuid,
    p_success boolean,
    p_usage jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_config jsonb;
    v_timer boolean;
    v_elapsed integer;
    v_next_status text;
    v_reservation record;
    v_usage jsonb;
    v_remaining numeric(14,3);
    v_used numeric(14,3);
    v_unused numeric(14,3);
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    if p_usage is null or jsonb_typeof(p_usage) <> 'array'
       or jsonb_array_length(p_usage) > 100 then
        raise exception 'Confirme o uso das pecas reservadas.';
    end if;

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null
    for update;

    if not found or v_ticket.status <> 'Andamento Reparo'
       or v_ticket.repair_start_at is null then
        raise exception 'A OS nao esta disponivel para finalizar reparo.';
    end if;
    if not (
        v_ctx.is_admin
        or (
            v_ctx.is_technician
            and v_ticket.technician_id = v_ctx.actor_employee_id
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode finalizar o reparo.';
    end if;

    for v_reservation in
        select r.*, tp.ticket_id
        from public.inventory_reservations r
        join public.ticket_part_items tp
          on tp.workspace_id = r.workspace_id and tp.id = r.ticket_part_item_id
        where r.workspace_id = v_ctx.workspace_id
          and tp.ticket_id = p_ticket_id
          and r.status = 'active'
        order by r.item_id, r.location_id, r.id
        for update of r
    loop
        v_remaining := v_reservation.reserved_quantity
            - v_reservation.consumed_quantity
            - v_reservation.released_quantity;
        if v_remaining <= 0 then continue; end if;

        select value into v_usage
        from jsonb_array_elements(p_usage)
        where value ->> 'reservation_id' = v_reservation.id::text
        limit 1;
        if v_usage is null then
            raise exception 'Confirme a quantidade usada de todas as pecas reservadas.';
        end if;
        begin
            v_used := (v_usage ->> 'used_quantity')::numeric;
        exception when others then
            raise exception 'Quantidade utilizada invalida.';
        end;
        if v_used is null or v_used < 0 or v_used > v_remaining then
            raise exception 'A quantidade usada nao pode exceder a reserva.';
        end if;
        v_unused := v_remaining - v_used;

        update public.inventory_balances
        set physical_quantity = physical_quantity - v_used,
            reserved_quantity = reserved_quantity - v_remaining,
            updated_at = now()
        where workspace_id = v_ctx.workspace_id
          and item_id = v_reservation.item_id
          and location_id = v_reservation.location_id;

        if v_used > 0 then
            insert into public.inventory_movements(
                workspace_id, item_id, location_id, movement_type,
                physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
                reason, actor_user_id, actor_employee_id, actor_name
            ) values (
                v_ctx.workspace_id, v_reservation.item_id,
                v_reservation.location_id, 'consume',
                -v_used, -v_used, p_ticket_id, v_reservation.ticket_part_item_id,
                'Peca utilizada no reparo',
                v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
            );
        end if;
        if v_unused > 0 then
            insert into public.inventory_movements(
                workspace_id, item_id, location_id, movement_type,
                physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
                reason, actor_user_id, actor_employee_id, actor_name
            ) values (
                v_ctx.workspace_id, v_reservation.item_id,
                v_reservation.location_id, 'release',
                0, -v_unused, p_ticket_id, v_reservation.ticket_part_item_id,
                'Peca reservada nao utilizada',
                v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
            );
        end if;

        update public.inventory_reservations
        set consumed_quantity = consumed_quantity + v_used,
            released_quantity = released_quantity + v_unused,
            status = case when v_used > 0 then 'consumed' else 'released' end,
            updated_at = now()
        where id = v_reservation.id and workspace_id = v_ctx.workspace_id;
    end loop;

    update public.ticket_part_items tp
    set status = case
            when exists (
                select 1 from public.inventory_reservations r
                where r.workspace_id = tp.workspace_id
                  and r.ticket_part_item_id = tp.id
                  and r.consumed_quantity > 0
            ) then 'consumed'
            else 'released'
        end,
        updated_at = now()
    where tp.workspace_id = v_ctx.workspace_id
      and tp.ticket_id = p_ticket_id
      and tp.status in ('reserved', 'ready');

    perform private.inventory_sync_ticket_summary(v_ctx.workspace_id, p_ticket_id);

    select coalesce(w.tracker_config, '{}'::jsonb)
    into v_config from public.workspaces w where w.id = v_ctx.workspace_id;
    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := case
        when v_timer then coalesce(v_ticket.repair_elapsed_seconds, 0)
            + greatest(0, extract(epoch from (now() - v_ticket.repair_start_at))::integer)
        else 0
    end;
    v_next_status := case
        when p_success and public.aida_config_bool(v_config, 'workflow', 'final_test', true)
            then 'Teste Final'
        else 'Retirada Cliente'
    end;

    update public.tickets
    set status = v_next_status,
        repair_successful = p_success,
        repair_elapsed_seconds = v_elapsed,
        repair_end_at = now(),
        repair_start_at = null,
        repair_paused_at = null,
        updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_ticket_id;

    update public.ticket_appointments
    set status = 'completed',
        actual_start = coalesce(actual_start, now()),
        actual_end = now(),
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = now()
    where id = (
        select a.id from public.ticket_appointments a
        where a.workspace_id = v_ctx.workspace_id
          and a.ticket_id = p_ticket_id
          and a.appointment_type = 'repair'
          and a.status in ('scheduled', 'in_progress')
          and a.deleted_at is null
        order by a.created_at desc limit 1
    );

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        'Finalizou Reparo',
        format(
            'O reparo da **OS %s**, aparelho **%s** de **%s**, foi finalizado por **%s** com resultado **%s**. As peças utilizadas foram baixadas e as não utilizadas voltaram ao disponível.%s',
            coalesce(v_ticket.os_number, 'não informada'),
            coalesce(v_ticket.device_model, 'não informado'),
            coalesce(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name,
            case when p_success then 'sucesso' else 'sem reparo' end,
            case when v_timer
                then format(' Tempo total: **%s segundos**.', v_elapsed)
                else ''
            end
        ),
        v_ctx.actor_name
    );

    return jsonb_build_object(
        'success', true,
        'status', v_next_status,
        'elapsed_seconds', v_elapsed
    );
end;
$$;

revoke all on function public.complete_repair_with_inventory(uuid, boolean, jsonb)
from public;
grant execute on function public.complete_repair_with_inventory(uuid, boolean, jsonb)
to anon, authenticated;

commit;
