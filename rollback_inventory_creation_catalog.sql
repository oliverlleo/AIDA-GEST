begin;

drop function if exists public.get_inventory_creation_catalog_page(
    text,
    text,
    integer,
    jsonb
);

commit;
