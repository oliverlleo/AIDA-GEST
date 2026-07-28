-- Completa a auditoria imutavel com saldos anterior e posterior.
begin;

alter table public.inventory_movements
    add column if not exists physical_before numeric(14,3),
    add column if not exists physical_after numeric(14,3),
    add column if not exists reserved_before numeric(14,3),
    add column if not exists reserved_after numeric(14,3),
    add column if not exists counterpart_location_id uuid;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'inventory_movements_counterpart_location_fkey'
          and conrelid = 'public.inventory_movements'::regclass
    ) then
        alter table public.inventory_movements
            add constraint inventory_movements_counterpart_location_fkey
            foreign key (workspace_id, counterpart_location_id)
            references public.inventory_locations(workspace_id, id)
            on delete restrict;
    end if;
end;
$$;

create or replace function private.inventory_fill_movement_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_physical numeric(14,3);
    v_reserved numeric(14,3);
begin
    select b.physical_quantity, b.reserved_quantity
    into v_physical, v_reserved
    from public.inventory_balances b
    where b.workspace_id = new.workspace_id
      and b.item_id = new.item_id
      and b.location_id = new.location_id;
    v_physical := coalesce(v_physical, 0);
    v_reserved := coalesce(v_reserved, 0);
    new.physical_after := v_physical;
    new.reserved_after := v_reserved;
    new.physical_before := v_physical - new.physical_delta;
    new.reserved_before := v_reserved - new.reserved_delta;
    return new;
end;
$$;

revoke all on function private.inventory_fill_movement_snapshot()
from public, anon, authenticated;
drop trigger if exists inventory_fill_movement_snapshot on public.inventory_movements;
create trigger inventory_fill_movement_snapshot
before insert on public.inventory_movements
for each row execute function private.inventory_fill_movement_snapshot();

commit;
