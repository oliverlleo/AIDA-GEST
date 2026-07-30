begin;

create index if not exists inventory_reservations_active_item_page_idx
    on public.inventory_reservations (
        workspace_id,
        item_id,
        created_at desc,
        ticket_part_item_id,
        id
    )
    include (
        location_id,
        reserved_quantity,
        consumed_quantity,
        released_quantity
    )
    where status = 'active';

create or replace function public.get_inventory_item_reservations_page(
    p_item_id uuid,
    p_limit integer default 20,
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
    v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
    v_result jsonb;
begin
    select * into v_ctx
    from public.get_current_actor_context();

    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    if p_item_id is null or not exists (
        select 1
        from public.inventory_items i
        where i.workspace_id = v_ctx.workspace_id
          and i.id = p_item_id
    ) then
        raise exception 'Item não encontrado.';
    end if;

    with reservation_totals as materialized (
        select
            t.id,
            t.os_number,
            t.client_name,
            t.device_model,
            t.status,
            t.technician_id,
            e.name as technician_name,
            t.warranty_claim,
            sum(
                r.reserved_quantity
                - r.consumed_quantity
                - r.released_quantity
            ) as reserved_quantity,
            min(r.created_at) as reserved_at,
            array_agg(
                distinct coalesce(
                    case
                        when g.id is not null then g.name || ' · ' || l.name
                        else null
                    end,
                    l.normalized_address,
                    l.name
                )
            ) as locations
        from public.inventory_reservations r
        join public.ticket_part_items tp
          on tp.workspace_id = r.workspace_id
         and tp.id = r.ticket_part_item_id
        join public.tickets t
          on t.workspace_id = tp.workspace_id
         and t.id = tp.ticket_id
        join public.inventory_locations l
          on l.workspace_id = r.workspace_id
         and l.id = r.location_id
        left join public.inventory_location_groups g
          on g.workspace_id = l.workspace_id
         and g.id = l.group_id
        left join public.employees e
          on e.workspace_id = t.workspace_id
         and e.id = t.technician_id
         and e.deleted_at is null
        where r.workspace_id = v_ctx.workspace_id
          and r.item_id = p_item_id
          and r.status = 'active'
          and r.reserved_quantity > r.consumed_quantity + r.released_quantity
          and t.deleted_at is null
        group by
            t.id,
            t.os_number,
            t.client_name,
            t.device_model,
            t.status,
            t.technician_id,
            e.name,
            t.warranty_claim
    ),
    page_rows as materialized (
        select rt.*
        from reservation_totals rt
        where p_cursor is null
           or (rt.reserved_at, rt.id) < (
                nullif(p_cursor ->> 'reserved_at', '')::timestamptz,
                nullif(p_cursor ->> 'ticket_id', '')::uuid
           )
        order by rt.reserved_at desc, rt.id desc
        limit v_limit + 1
    ),
    visible_rows as materialized (
        select pr.*
        from page_rows pr
        order by pr.reserved_at desc, pr.id desc
        limit v_limit
    )
    select jsonb_build_object(
        'total', (select count(*) from reservation_totals),
        'items', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'id', vr.id,
                    'os_number', vr.os_number,
                    'client_name', vr.client_name,
                    'device_model', vr.device_model,
                    'status', vr.status,
                    'technician_id', vr.technician_id,
                    'technician_name', vr.technician_name,
                    'warranty_claim', coalesce(vr.warranty_claim, false),
                    'reserved_quantity', vr.reserved_quantity,
                    'reserved_at', vr.reserved_at,
                    'locations', to_jsonb(vr.locations),
                    '_card_summary', true
                )
                order by vr.reserved_at desc, vr.id desc
            )
            from visible_rows vr
        ), '[]'::jsonb),
        'has_more', (select count(*) > v_limit from page_rows),
        'next_cursor', (
            select jsonb_build_object(
                'reserved_at', tail.reserved_at,
                'ticket_id', tail.id
            )
            from (
                select vr.*
                from visible_rows vr
                order by vr.reserved_at asc, vr.id asc
                limit 1
            ) tail
        )
    )
    into v_result;

    return v_result;
end;
$$;

comment on function public.get_inventory_item_reservations_page(uuid, integer, jsonb)
is 'Lista paginada das OS que mantêm reserva ativa de um item, limitada ao workspace do ator.';

revoke all on function public.get_inventory_item_reservations_page(uuid, integer, jsonb) from public;
grant execute on function public.get_inventory_item_reservations_page(uuid, integer, jsonb) to anon, authenticated;

commit;
