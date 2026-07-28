-- A versao base e restaurada por rollback_inventory_module.sql.
begin;
drop function if exists public.save_inventory_location(jsonb);
commit;
