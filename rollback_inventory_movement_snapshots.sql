begin;
drop trigger if exists inventory_fill_movement_snapshot on public.inventory_movements;
drop function if exists private.inventory_fill_movement_snapshot();
alter table public.inventory_movements
    drop constraint if exists inventory_movements_counterpart_location_fkey,
    drop column if exists counterpart_location_id,
    drop column if exists reserved_after,
    drop column if exists reserved_before,
    drop column if exists physical_after,
    drop column if exists physical_before;
commit;
