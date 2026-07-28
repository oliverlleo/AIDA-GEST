begin;
drop function if exists public.register_inventory_entry(uuid, uuid, numeric, numeric, text);
alter table public.inventory_movements
    drop constraint if exists inventory_movements_type_check;
alter table public.inventory_movements
    add constraint inventory_movements_type_check check (
        movement_type in (
            'opening', 'purchase_receipt', 'reserve', 'release',
            'consume', 'return', 'adjustment', 'transfer_out', 'transfer_in'
        )
    );
commit;
