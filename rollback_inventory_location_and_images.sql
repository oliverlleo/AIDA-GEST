begin;

drop function if exists public.manage_inventory_location(uuid, text);
drop function if exists public.generate_inventory_locations(text, int, int, text, text, int, int);
drop function if exists public.set_inventory_item_locations(uuid, uuid[], uuid);

drop policy if exists aida_inventory_images_select on storage.objects;
drop policy if exists aida_inventory_images_insert on storage.objects;
drop policy if exists aida_inventory_images_update on storage.objects;
drop policy if exists aida_inventory_images_delete on storage.objects;

delete from storage.buckets b
where b.id = 'inventory_images'
  and not exists (select 1 from storage.objects o where o.bucket_id = b.id);

commit;