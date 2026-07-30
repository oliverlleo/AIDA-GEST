begin;
drop function if exists public.return_ticket_inventory(uuid, numeric, text);
alter table public.inventory_reservations
    drop constraint if exists inventory_reservations_quantities_check,
    drop column if exists returned_quantity;
alter table public.inventory_reservations
    add constraint inventory_reservations_quantities_check check (
        reserved_quantity > 0
        and consumed_quantity >= 0
        and released_quantity >= 0
        and consumed_quantity + released_quantity <= reserved_quantity
    );
commit;
