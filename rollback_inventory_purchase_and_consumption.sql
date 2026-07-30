begin;

drop function if exists public.complete_repair_with_inventory(uuid, boolean, jsonb);
drop function if exists public.get_ticket_inventory_parts(uuid);
drop function if exists public.receive_inventory_purchase(uuid, jsonb, boolean);
drop function if exists private.inventory_resume_ready_ticket(uuid, uuid);
drop function if exists public.create_inventory_purchase(uuid, jsonb, boolean, text);

commit;
