begin;

drop trigger if exists aida_release_inventory_on_ticket_transition on public.tickets;

drop function if exists public.approve_ticket_with_inventory(uuid);
drop function if exists public.request_ticket_inventory_parts(uuid, jsonb, text, boolean);
drop function if exists private.inventory_release_on_ticket_transition();
drop function if exists private.inventory_release_ticket_reservations(uuid, uuid, text);
drop function if exists private.inventory_pause_repair_for_shortage(uuid, uuid, jsonb);
drop function if exists private.inventory_allocate_ticket_parts(uuid, uuid);
drop function if exists private.inventory_sync_ticket_summary(uuid, uuid);

commit;
