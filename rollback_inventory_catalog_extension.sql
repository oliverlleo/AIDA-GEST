-- A assinatura e restaurada integralmente por rollback_inventory_module.sql.
begin;
drop function if exists public.save_inventory_item(jsonb);
commit;
