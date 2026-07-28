-- Rollback do modulo opcional de estoque.
-- Nao altera OS, parts_needed, parts_status ou supplier_purchases legados.

begin;

drop trigger if exists aida_validate_inventory_tracker_config on public.workspaces;
drop trigger if exists inventory_movements_block_mutation on public.inventory_movements;

drop function if exists public.adjust_inventory_stock(uuid, uuid, numeric, text);
drop function if exists public.save_inventory_location(jsonb);
drop function if exists public.save_inventory_item(jsonb);
drop function if exists public.get_inventory_catalog_page(uuid, text, integer, jsonb);
drop function if exists public.get_inventory_items_page(text, text, text, integer, jsonb);
drop function if exists public.get_inventory_dashboard();

drop function if exists private.validate_inventory_tracker_config();
drop function if exists private.inventory_movements_immutable();
drop function if exists private.inventory_assert_access(uuid, text);
drop function if exists private.inventory_config_enabled(uuid);

drop table if exists public.inventory_movements;
drop table if exists public.inventory_purchase_allocations;
drop table if exists public.inventory_purchase_items;
drop table if exists public.inventory_purchases;
drop table if exists public.inventory_reservations;
drop table if exists public.ticket_part_items;
drop table if exists public.inventory_item_relations;
drop table if exists public.inventory_item_suppliers;
drop table if exists public.inventory_item_models;
drop table if exists public.inventory_balances;

alter table if exists public.inventory_items
    drop constraint if exists inventory_items_default_location_fkey;
alter table if exists public.inventory_items
    drop column if exists default_location_id;

drop table if exists public.inventory_locations;
drop table if exists public.inventory_location_schemes;
drop table if exists public.inventory_item_costs;
drop table if exists public.inventory_items;

drop index if exists public.device_models_workspace_id_id_uidx;
drop index if exists public.fornecedores_workspace_id_id_uidx;

commit;
