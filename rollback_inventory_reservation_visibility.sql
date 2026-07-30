begin;

drop function if exists public.get_inventory_item_reservations_page(uuid, integer, jsonb);
drop index if exists public.inventory_reservations_active_item_page_idx;

commit;
