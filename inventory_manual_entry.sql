-- Entrada manual com custo opcional e atualizacao do custo medio.
begin;

alter table public.inventory_movements
    drop constraint if exists inventory_movements_type_check;
alter table public.inventory_movements
    add constraint inventory_movements_type_check check (
        movement_type in (
            'opening', 'manual_entry', 'purchase_receipt', 'reserve', 'release',
            'consume', 'return', 'adjustment', 'transfer_out', 'transfer_in'
        )
    );

create or replace function public.register_inventory_entry(
    p_item_id uuid,
    p_location_id uuid,
    p_quantity numeric,
    p_unit_cost numeric default null,
    p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_item public.inventory_items%rowtype;
    v_total_physical numeric(14,3);
    v_old_average numeric(14,4);
    v_new_average numeric(14,4);
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_quantity is null or p_quantity <= 0
       or (p_unit_cost is not null and p_unit_cost < 0)
       or length(btrim(coalesce(p_reason, ''))) < 5 then
        raise exception 'Informe quantidade, custo e motivo validos.';
    end if;
    select * into v_item from public.inventory_items i
    where i.workspace_id = v_ctx.workspace_id and i.id = p_item_id and i.active
    for update;
    if not found or not v_item.track_stock then raise exception 'Item controlado nao encontrado.'; end if;
    if not v_item.allow_decimal and p_quantity <> trunc(p_quantity) then
        raise exception 'Este item aceita apenas quantidades inteiras.';
    end if;
    if not exists (
        select 1 from public.inventory_locations l
        where l.workspace_id = v_ctx.workspace_id and l.id = p_location_id and l.active
    ) then raise exception 'Localizacao invalida.'; end if;

    select coalesce(sum(b.physical_quantity), 0) into v_total_physical
    from public.inventory_balances b
    where b.workspace_id = v_ctx.workspace_id and b.item_id = p_item_id;
    select coalesce(c.average_cost, 0) into v_old_average
    from public.inventory_item_costs c
    where c.workspace_id = v_ctx.workspace_id and c.item_id = p_item_id
    for update;
    insert into public.inventory_balances(
        workspace_id, item_id, location_id, physical_quantity, reserved_quantity
    ) values (v_ctx.workspace_id, p_item_id, p_location_id, 0, 0)
    on conflict (workspace_id, item_id, location_id) do nothing;
    perform 1 from public.inventory_balances b
    where b.workspace_id = v_ctx.workspace_id
      and b.item_id = p_item_id and b.location_id = p_location_id
    for update;
    update public.inventory_balances
    set physical_quantity = physical_quantity + p_quantity, updated_at = now()
    where workspace_id = v_ctx.workspace_id
      and item_id = p_item_id and location_id = p_location_id;

    if p_unit_cost is not null then
        v_new_average := (
            (v_total_physical * v_old_average) + (p_quantity * p_unit_cost)
        ) / (v_total_physical + p_quantity);
        update public.inventory_item_costs
        set average_cost = v_new_average,
            last_cost = p_unit_cost,
            updated_at = now()
        where workspace_id = v_ctx.workspace_id and item_id = p_item_id;
    else
        v_new_average := v_old_average;
    end if;
    insert into public.inventory_movements(
        workspace_id, item_id, location_id, movement_type,
        physical_delta, unit_cost_snapshot, reason,
        actor_user_id, actor_employee_id, actor_name
    ) values (
        v_ctx.workspace_id, p_item_id, p_location_id, 'manual_entry',
        p_quantity, p_unit_cost, btrim(p_reason),
        v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
    );
    return jsonb_build_object(
        'success', true,
        'average_cost', v_new_average
    );
end;
$$;

revoke all on function public.register_inventory_entry(uuid, uuid, numeric, numeric, text)
from public;
grant execute on function public.register_inventory_entry(uuid, uuid, numeric, numeric, text)
to anon, authenticated;

commit;
