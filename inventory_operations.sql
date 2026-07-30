-- Operacoes administrativas, consultas sob demanda e relacionamentos do estoque.
-- Depende de inventory_module_foundation.sql, inventory_workflow_integration.sql
-- e inventory_purchase_and_consumption.sql.

begin;

alter table public.inventory_items
    add column if not exists universal_code text,
    add column if not exists internal_notes text,
    add column if not exists image_url text,
    add column if not exists last_purchase_at timestamptz;

create unique index if not exists inventory_items_workspace_universal_code_uq
    on public.inventory_items(workspace_id, lower(btrim(universal_code)))
    where universal_code is not null and btrim(universal_code) <> '';

alter table public.inventory_item_suppliers
    add column if not exists purchase_url text,
    add column if not exists minimum_order_quantity numeric(14,3),
    add column if not exists notes text,
    add column if not exists last_purchase_at timestamptz;

alter table public.inventory_item_suppliers
    drop constraint if exists inventory_item_suppliers_values_check;
alter table public.inventory_item_suppliers
    add constraint inventory_item_suppliers_values_check check (
        (last_price is null or last_price >= 0)
        and (lead_time_days is null or lead_time_days >= 0)
        and (minimum_order_quantity is null or minimum_order_quantity > 0)
    );

alter table public.inventory_purchases
    add column if not exists discount_amount numeric(14,2) not null default 0,
    add column if not exists surcharge_amount numeric(14,2) not null default 0;

alter table public.inventory_purchases
    drop constraint if exists inventory_purchases_adjustments_check;
alter table public.inventory_purchases
    add constraint inventory_purchases_adjustments_check check (
        discount_amount >= 0 and surcharge_amount >= 0
    );

alter table public.inventory_purchase_items
    add column if not exists supplier_sku_snapshot text;

create or replace function public.get_inventory_locations()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    return jsonb_build_object(
        'locations', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', l.id,
                'name', l.name,
                'normalized_address', l.normalized_address,
                'scheme_id', l.scheme_id,
                'address_components', l.address_components,
                'active', l.active
            ) order by l.active desc, l.normalized_address, l.id)
            from public.inventory_locations l
            where l.workspace_id = v_ctx.workspace_id
        ), '[]'::jsonb),
        'schemes', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', s.id,
                'name', s.name,
                'mode', s.mode,
                'component_labels', s.component_labels,
                'active', s.active
            ) order by s.active desc, lower(s.name), s.id)
            from public.inventory_location_schemes s
            where s.workspace_id = v_ctx.workspace_id
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public.get_inventory_locations() from public;
grant execute on function public.get_inventory_locations() to anon, authenticated;

create or replace function public.save_inventory_location_scheme(p_scheme jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_id uuid;
    v_name text;
    v_mode text;
    v_components jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_scheme is null or jsonb_typeof(p_scheme) <> 'object' then
        raise exception 'Dados do padrao invalidos.';
    end if;

    v_id := nullif(p_scheme ->> 'id', '')::uuid;
    v_name := btrim(coalesce(p_scheme ->> 'name', ''));
    v_mode := coalesce(nullif(p_scheme ->> 'mode', ''), 'free');
    v_components := coalesce(p_scheme -> 'component_labels', '[]'::jsonb);
    if length(v_name) < 2 or v_mode not in ('free', 'structured')
       or jsonb_typeof(v_components) <> 'array'
       or jsonb_array_length(v_components) > 8 then
        raise exception 'Padrao de endereco invalido.';
    end if;

    if v_mode = 'structured' and exists (
        select 1 from jsonb_array_elements(v_components) c
        where c ->> 'type' not in ('letters', 'numbers', 'alphanumeric', 'fixed', 'separator', 'options')
           or length(btrim(coalesce(c ->> 'label', ''))) > 40
    ) then
        raise exception 'O padrao possui uma parte invalida.';
    end if;

    if v_id is null then
        insert into public.inventory_location_schemes(
            workspace_id, name, mode, component_labels
        ) values (v_ctx.workspace_id, v_name, v_mode, v_components)
        returning id into v_id;
    else
        update public.inventory_location_schemes s
        set name = v_name,
            mode = v_mode,
            component_labels = v_components,
            updated_at = now()
        where s.workspace_id = v_ctx.workspace_id and s.id = v_id;
        if not found then raise exception 'Padrao nao encontrado.'; end if;
    end if;
    return v_id;
end;
$$;

revoke all on function public.save_inventory_location_scheme(jsonb) from public;
grant execute on function public.save_inventory_location_scheme(jsonb) to anon, authenticated;

create or replace function public.get_inventory_item_detail(p_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_item public.inventory_items%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');
    select * into v_item from public.inventory_items i
    where i.workspace_id = v_ctx.workspace_id and i.id = p_item_id;
    if not found then raise exception 'Item nao encontrado.'; end if;

    return jsonb_build_object(
        'item', to_jsonb(v_item),
        'cost', coalesce((
            select jsonb_build_object(
                'average_cost', c.average_cost,
                'last_cost', c.last_cost,
                'updated_at', c.updated_at
            ) from public.inventory_item_costs c
            where c.workspace_id = v_ctx.workspace_id and c.item_id = p_item_id
        ), '{}'::jsonb),
        'balances', coalesce((
            select jsonb_agg(jsonb_build_object(
                'location_id', b.location_id,
                'location_name', l.name,
                'address', l.normalized_address,
                'physical_quantity', b.physical_quantity,
                'reserved_quantity', b.reserved_quantity,
                'available_quantity', b.available_quantity
            ) order by l.normalized_address, l.id)
            from public.inventory_balances b
            join public.inventory_locations l
              on l.workspace_id = b.workspace_id and l.id = b.location_id
            where b.workspace_id = v_ctx.workspace_id and b.item_id = p_item_id
        ), '[]'::jsonb),
        'suppliers', coalesce((
            select jsonb_agg(jsonb_build_object(
                'supplier_id', s.supplier_id,
                'supplier_name', f.razao_social,
                'supplier_sku', s.supplier_sku,
                'purchase_url', s.purchase_url,
                'last_price', s.last_price,
                'lead_time_days', s.lead_time_days,
                'minimum_order_quantity', s.minimum_order_quantity,
                'preferred', s.preferred,
                'notes', s.notes,
                'last_purchase_at', s.last_purchase_at
            ) order by s.preferred desc, lower(f.razao_social), f.id)
            from public.inventory_item_suppliers s
            join public.fornecedores f
              on f.workspace_id = s.workspace_id and f.id = s.supplier_id
            where s.workspace_id = v_ctx.workspace_id and s.item_id = p_item_id
        ), '[]'::jsonb),
        'model_ids', coalesce((
            select jsonb_agg(m.device_model_id order by m.device_model_id)
            from public.inventory_item_models m
            where m.workspace_id = v_ctx.workspace_id and m.item_id = p_item_id
        ), '[]'::jsonb),
        'relations', coalesce((
            select jsonb_agg(jsonb_build_object(
                'target_item_id', r.target_item_id,
                'target_name', i.name,
                'relation_type', r.relation_type,
                'available_quantity', coalesce((
                    select sum(b.available_quantity)
                    from public.inventory_balances b
                    where b.workspace_id = r.workspace_id and b.item_id = r.target_item_id
                ), 0)
            ) order by r.relation_type, lower(i.name), i.id)
            from public.inventory_item_relations r
            join public.inventory_items i
              on i.workspace_id = r.workspace_id and i.id = r.target_item_id
            where r.workspace_id = v_ctx.workspace_id and r.source_item_id = p_item_id
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public.get_inventory_item_detail(uuid) from public;
grant execute on function public.get_inventory_item_detail(uuid) to anon, authenticated;

create or replace function public.save_inventory_item_links(
    p_item_id uuid,
    p_model_ids jsonb default '[]'::jsonb,
    p_suppliers jsonb default '[]'::jsonb,
    p_relations jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_value jsonb;
    v_supplier_id uuid;
    v_target_id uuid;
    v_type text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if not exists (
        select 1 from public.inventory_items i
        where i.workspace_id = v_ctx.workspace_id and i.id = p_item_id
    ) then raise exception 'Item nao encontrado.'; end if;
    if jsonb_typeof(coalesce(p_model_ids, '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_suppliers, '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_relations, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_model_ids, '[]'::jsonb)) > 200
       or jsonb_array_length(coalesce(p_suppliers, '[]'::jsonb)) > 100
       or jsonb_array_length(coalesce(p_relations, '[]'::jsonb)) > 100 then
        raise exception 'Relacionamentos invalidos.';
    end if;

    delete from public.inventory_item_models
    where workspace_id = v_ctx.workspace_id and item_id = p_item_id;
    for v_value in select value from jsonb_array_elements(coalesce(p_model_ids, '[]'::jsonb))
    loop
        insert into public.inventory_item_models(workspace_id, item_id, device_model_id)
        select v_ctx.workspace_id, p_item_id, (v_value #>> '{}')::uuid
        where exists (
            select 1 from public.device_models d
            where d.workspace_id = v_ctx.workspace_id and d.id = (v_value #>> '{}')::uuid
        )
        on conflict do nothing;
    end loop;

    delete from public.inventory_item_suppliers
    where workspace_id = v_ctx.workspace_id and item_id = p_item_id;
    for v_value in select value from jsonb_array_elements(coalesce(p_suppliers, '[]'::jsonb))
    loop
        v_supplier_id := (v_value ->> 'supplier_id')::uuid;
        if not exists (
            select 1 from public.fornecedores f
            where f.workspace_id = v_ctx.workspace_id and f.id = v_supplier_id
        ) then raise exception 'Fornecedor vinculado invalido.'; end if;
        insert into public.inventory_item_suppliers(
            workspace_id, item_id, supplier_id, supplier_sku, purchase_url,
            last_price, lead_time_days, preferred, minimum_order_quantity, notes
        ) values (
            v_ctx.workspace_id, p_item_id, v_supplier_id,
            nullif(btrim(v_value ->> 'supplier_sku'), ''),
            nullif(btrim(v_value ->> 'purchase_url'), ''),
            nullif(v_value ->> 'last_price', '')::numeric,
            nullif(v_value ->> 'lead_time_days', '')::integer,
            coalesce((v_value ->> 'preferred')::boolean, false),
            nullif(v_value ->> 'minimum_order_quantity', '')::numeric,
            nullif(btrim(v_value ->> 'notes'), '')
        );
    end loop;

    delete from public.inventory_item_relations
    where workspace_id = v_ctx.workspace_id and source_item_id = p_item_id;
    for v_value in select value from jsonb_array_elements(coalesce(p_relations, '[]'::jsonb))
    loop
        v_target_id := (v_value ->> 'target_item_id')::uuid;
        v_type := v_value ->> 'relation_type';
        if v_target_id = p_item_id or v_type not in ('equivalent', 'substitute')
           or not exists (
               select 1 from public.inventory_items i
               where i.workspace_id = v_ctx.workspace_id and i.id = v_target_id
           ) then raise exception 'Relacao de peca invalida.'; end if;
        insert into public.inventory_item_relations(
            workspace_id, source_item_id, target_item_id, relation_type
        ) values (v_ctx.workspace_id, p_item_id, v_target_id, v_type)
        on conflict do nothing;
        if v_type = 'equivalent' then
            insert into public.inventory_item_relations(
                workspace_id, source_item_id, target_item_id, relation_type
            ) values (v_ctx.workspace_id, v_target_id, p_item_id, v_type)
            on conflict do nothing;
        end if;
    end loop;
    return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.save_inventory_item_links(uuid, jsonb, jsonb, jsonb) from public;
grant execute on function public.save_inventory_item_links(uuid, jsonb, jsonb, jsonb)
to anon, authenticated;

create or replace function public.transfer_inventory(
    p_item_id uuid,
    p_from_location_id uuid,
    p_to_location_id uuid,
    p_quantity numeric,
    p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_item public.inventory_items%rowtype;
    v_from public.inventory_balances%rowtype;
    v_group uuid := gen_random_uuid();
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_from_location_id = p_to_location_id or p_quantity is null or p_quantity <= 0
       or length(btrim(coalesce(p_reason, ''))) < 5 then
        raise exception 'Informe origem, destino, quantidade e motivo validos.';
    end if;
    select * into v_item from public.inventory_items i
    where i.workspace_id = v_ctx.workspace_id and i.id = p_item_id and i.active
    for update;
    if not found or not v_item.track_stock then raise exception 'Item invalido.'; end if;
    if not v_item.allow_decimal and p_quantity <> trunc(p_quantity) then
        raise exception 'Este item aceita apenas quantidades inteiras.';
    end if;
    if not exists (
        select 1 from public.inventory_locations l
        where l.workspace_id = v_ctx.workspace_id and l.id = p_to_location_id and l.active
    ) then raise exception 'Local de destino invalido.'; end if;

    select * into v_from from public.inventory_balances b
    where b.workspace_id = v_ctx.workspace_id
      and b.item_id = p_item_id and b.location_id = p_from_location_id
    for update;
    if not found or v_from.available_quantity < p_quantity then
        raise exception 'Saldo disponivel insuficiente na origem.';
    end if;
    insert into public.inventory_balances(
        workspace_id, item_id, location_id, physical_quantity, reserved_quantity
    ) values (v_ctx.workspace_id, p_item_id, p_to_location_id, 0, 0)
    on conflict (workspace_id, item_id, location_id) do nothing;
    perform 1 from public.inventory_balances b
    where b.workspace_id = v_ctx.workspace_id
      and b.item_id = p_item_id and b.location_id = p_to_location_id
    for update;

    update public.inventory_balances set physical_quantity = physical_quantity - p_quantity, updated_at = now()
    where id = v_from.id;
    update public.inventory_balances set physical_quantity = physical_quantity + p_quantity, updated_at = now()
    where workspace_id = v_ctx.workspace_id and item_id = p_item_id and location_id = p_to_location_id;

    insert into public.inventory_movements(
        workspace_id, item_id, location_id, counterpart_location_id,
        movement_type, physical_delta, transfer_group_id, reason,
        actor_user_id, actor_employee_id, actor_name
    ) values
    (v_ctx.workspace_id, p_item_id, p_from_location_id, p_to_location_id,
     'transfer_out', -p_quantity, v_group, btrim(p_reason),
     v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name),
    (v_ctx.workspace_id, p_item_id, p_to_location_id, p_from_location_id,
     'transfer_in', p_quantity, v_group, btrim(p_reason),
     v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name);
    return jsonb_build_object('success', true, 'transfer_group_id', v_group);
end;
$$;

revoke all on function public.transfer_inventory(uuid, uuid, uuid, numeric, text) from public;
grant execute on function public.transfer_inventory(uuid, uuid, uuid, numeric, text)
to anon, authenticated;

create or replace function public.archive_inventory_item(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if exists (
        select 1 from public.inventory_reservations r
        where r.workspace_id = v_ctx.workspace_id and r.item_id = p_item_id
          and r.status = 'active'
          and r.reserved_quantity > r.consumed_quantity + r.released_quantity
    ) or exists (
        select 1 from public.inventory_purchase_items pi
        join public.inventory_purchases p
          on p.workspace_id = pi.workspace_id and p.id = pi.purchase_id
        where pi.workspace_id = v_ctx.workspace_id and pi.item_id = p_item_id
          and p.status in ('draft', 'ordered', 'partial')
    ) then raise exception 'Conclua reservas e compras abertas antes de arquivar o item.'; end if;
    update public.inventory_items set active = false, updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_item_id;
    if not found then raise exception 'Item nao encontrado.'; end if;
    return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.archive_inventory_item(uuid) from public;
grant execute on function public.archive_inventory_item(uuid) to anon, authenticated;

create or replace function public.get_inventory_movements_page(
    p_item_id uuid default null,
    p_limit integer default 30,
    p_cursor jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_created_at timestamptz;
    v_id uuid;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');
    if p_limit < 1 or p_limit > 50 then raise exception 'Limite invalido.'; end if;
    if p_cursor is not null then
        begin
            v_created_at := (p_cursor ->> 'created_at')::timestamptz;
            v_id := (p_cursor ->> 'id')::uuid;
        exception when others then raise exception 'Cursor invalido.';
        end;
    end if;
    with page_plus_one as materialized (
        select m.id, m.item_id, i.name item_name, m.location_id,
               l.name location_name, m.movement_type, m.physical_delta,
               m.reserved_delta, m.physical_before, m.physical_after,
               m.reserved_before, m.reserved_after, m.ticket_id, t.os_number, m.purchase_id,
               m.reason, m.actor_name, m.created_at
        from public.inventory_movements m
        join public.inventory_items i
          on i.workspace_id = m.workspace_id and i.id = m.item_id
        join public.inventory_locations l
          on l.workspace_id = m.workspace_id and l.id = m.location_id
        left join public.tickets t
          on t.workspace_id = m.workspace_id and t.id = m.ticket_id
        where m.workspace_id = v_ctx.workspace_id
          and (p_item_id is null or m.item_id = p_item_id)
          and (p_cursor is null or (m.created_at, m.id) < (v_created_at, v_id))
        order by m.created_at desc, m.id desc
        limit p_limit + 1
    ), page_rows as (
        select * from page_plus_one order by created_at desc, id desc limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc, p.id desc) from page_rows p), '[]'::jsonb),
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (select jsonb_build_object('created_at', p.created_at, 'id', p.id)
                        from page_rows p order by p.created_at, p.id limit 1)
    ) into v_result;
    return v_result;
end;
$$;

revoke all on function public.get_inventory_movements_page(uuid, integer, jsonb) from public;
grant execute on function public.get_inventory_movements_page(uuid, integer, jsonb)
to anon, authenticated;

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
                'ticket_ids', x.ticket_ids
            ) order by p.urgent desc, p.created_at, p.id)
            from public.inventory_purchases p
            join lateral (
                select count(*) item_count,
                       sum(pi.ordered_quantity) ordered_quantity,
                       sum(pi.received_quantity) received_quantity,
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

create or replace function public.allocate_received_inventory_purchase(p_purchase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket_id uuid;
    v_allocation jsonb;
    v_ready jsonb;
    v_results jsonb := '[]'::jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');
    if not exists (
        select 1 from public.inventory_purchases p
        where p.workspace_id = v_ctx.workspace_id and p.id = p_purchase_id
          and p.status in ('partial', 'received')
    ) then raise exception 'Compra recebida nao encontrada.'; end if;
    for v_ticket_id in
        select tp.ticket_id
        from public.inventory_purchase_items pi
        join public.inventory_purchase_allocations a
          on a.workspace_id = pi.workspace_id and a.purchase_item_id = pi.id
        join public.ticket_part_items tp
          on tp.workspace_id = a.workspace_id and tp.id = a.ticket_part_item_id
        join public.tickets t
          on t.workspace_id = tp.workspace_id and t.id = tp.ticket_id
        where pi.workspace_id = v_ctx.workspace_id and pi.purchase_id = p_purchase_id
        group by tp.ticket_id
        order by bool_or(coalesce(t.priority_requested, false)) desc,
                 min(tp.created_at), tp.ticket_id
    loop
        v_allocation := private.inventory_allocate_ticket_parts(v_ctx.workspace_id, v_ticket_id);
        if coalesce((v_allocation ->> 'fully_reserved')::boolean, false) then
            v_ready := private.inventory_resume_ready_ticket(v_ctx.workspace_id, v_ticket_id);
        else
            v_ready := jsonb_build_object('ready', false);
        end if;
        v_results := v_results || jsonb_build_array(jsonb_build_object(
            'ticket_id', v_ticket_id,
            'fully_reserved', coalesce((v_allocation ->> 'fully_reserved')::boolean, false),
            'resumed', coalesce((v_ready ->> 'resumed')::boolean, false)
        ));
    end loop;
    return jsonb_build_object('success', true, 'tickets', v_results);
end;
$$;

revoke all on function public.allocate_received_inventory_purchase(uuid) from public;
grant execute on function public.allocate_received_inventory_purchase(uuid)
to anon, authenticated;

create or replace function public.cancel_inventory_purchase(
    p_purchase_id uuid,
    p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_ctx record; v_purchase public.inventory_purchases%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');
    if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'Informe o motivo.'; end if;
    select * into v_purchase from public.inventory_purchases p
    where p.workspace_id = v_ctx.workspace_id and p.id = p_purchase_id
      and p.status in ('draft', 'ordered', 'partial')
    for update;
    if not found then raise exception 'Compra aberta nao encontrada.'; end if;
    if exists (
        select 1 from public.inventory_purchase_items pi
        where pi.workspace_id = v_ctx.workspace_id and pi.purchase_id = p_purchase_id
          and pi.received_quantity > 0
    ) then raise exception 'Compra com recebimento parcial nao pode ser cancelada; conclua o recebimento pendente.'; end if;
    update public.inventory_purchases set status = 'cancelled',
        cancelled_at = now(), notes = concat_ws(E'\n', notes, 'Cancelamento: ' || btrim(p_reason)),
        updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_purchase_id;
    update public.ticket_part_items tp set status = case
            when exists (
                select 1 from public.inventory_reservations r
                where r.workspace_id = tp.workspace_id and r.ticket_part_item_id = tp.id
                  and r.status = 'active'
            ) then 'partial' else 'purchase_pending' end,
        updated_at = now()
    where tp.workspace_id = v_ctx.workspace_id and exists (
        select 1 from public.inventory_purchase_allocations a
        join public.inventory_purchase_items pi
          on pi.workspace_id = a.workspace_id and pi.id = a.purchase_item_id
        where a.workspace_id = tp.workspace_id and a.ticket_part_item_id = tp.id
          and pi.purchase_id = p_purchase_id
    );
    return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.cancel_inventory_purchase(uuid, text) from public;
grant execute on function public.cancel_inventory_purchase(uuid, text)
to anon, authenticated;

-- Complementa o recebimento: quantidade recebida fica marcada na alocacao.
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
drop trigger if exists inventory_sync_purchase_fulfillment on public.inventory_purchase_items;
create trigger inventory_sync_purchase_fulfillment
after update of received_quantity on public.inventory_purchase_items
for each row when (new.received_quantity > old.received_quantity)
execute function private.inventory_sync_purchase_fulfillment();

commit;
