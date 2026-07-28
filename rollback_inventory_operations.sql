-- Execute somente depois de desativar o modulo e concluir operacoes abertas.
begin;

drop trigger if exists inventory_sync_purchase_fulfillment on public.inventory_purchase_items;
drop function if exists private.inventory_sync_purchase_fulfillment();
drop function if exists public.cancel_inventory_purchase(uuid, text);
drop function if exists public.allocate_received_inventory_purchase(uuid);
drop function if exists public.get_inventory_purchase_detail(uuid);
drop function if exists public.get_inventory_purchase_queue();
drop function if exists public.get_inventory_movements_page(uuid, integer, jsonb);
drop function if exists public.archive_inventory_item(uuid);
drop function if exists public.transfer_inventory(uuid, uuid, uuid, numeric, text);
drop function if exists public.save_inventory_item_links(uuid, jsonb, jsonb, jsonb);
drop function if exists public.get_inventory_item_detail(uuid);
drop function if exists public.save_inventory_location_scheme(jsonb);
drop function if exists public.get_inventory_locations();

drop index if exists public.inventory_items_workspace_universal_code_uq;
alter table public.inventory_purchase_items drop column if exists supplier_sku_snapshot;
alter table public.inventory_purchases
    drop constraint if exists inventory_purchases_adjustments_check,
    drop column if exists discount_amount,
    drop column if exists surcharge_amount;
alter table public.inventory_item_suppliers
    drop constraint if exists inventory_item_suppliers_values_check,
    drop column if exists purchase_url,
    drop column if exists minimum_order_quantity,
    drop column if exists notes,
    drop column if exists last_purchase_at;
alter table public.inventory_item_suppliers
    add constraint inventory_item_suppliers_values_check check (
        (last_price is null or last_price >= 0)
        and (lead_time_days is null or lead_time_days >= 0)
    );
alter table public.inventory_items
    drop column if exists universal_code,
    drop column if exists internal_notes,
    drop column if exists image_url,
    drop column if exists last_purchase_at;

commit;
