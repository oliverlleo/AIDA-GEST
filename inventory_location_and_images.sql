begin;

create or replace function public.set_inventory_item_locations(p_item_id uuid, p_location_ids uuid[], p_default_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ctx record; v_id uuid; v_ids uuid[] := coalesce(p_location_ids, array[]::uuid[]);
begin
 select * into v_ctx from public.get_current_actor_context();
 perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
 if not exists(select 1 from public.inventory_items i where i.workspace_id=v_ctx.workspace_id and i.id=p_item_id) then raise exception 'Item nao encontrado.'; end if;
 if exists(select 1 from unnest(v_ids) x(id) where not exists(select 1 from public.inventory_locations l where l.workspace_id=v_ctx.workspace_id and l.id=x.id and l.active)) then raise exception 'Uma localizacao selecionada e invalida.'; end if;
 if p_default_location_id is not null and not(p_default_location_id=any(v_ids)) then raise exception 'O local principal deve estar entre os locais selecionados.'; end if;
 foreach v_id in array v_ids loop
  insert into public.inventory_balances(workspace_id,item_id,location_id,physical_quantity,reserved_quantity) values(v_ctx.workspace_id,p_item_id,v_id,0,0) on conflict(workspace_id,item_id,location_id) do nothing;
 end loop;
 delete from public.inventory_balances b where b.workspace_id=v_ctx.workspace_id and b.item_id=p_item_id and b.physical_quantity=0 and b.reserved_quantity=0 and not(b.location_id=any(v_ids));
 update public.inventory_items set default_location_id=p_default_location_id,updated_at=now() where workspace_id=v_ctx.workspace_id and id=p_item_id;
 return jsonb_build_object('success',true,'location_count',cardinality(v_ids));
end;$$;
revoke all on function public.set_inventory_item_locations(uuid,uuid[],uuid) from public;
grant execute on function public.set_inventory_item_locations(uuid,uuid[],uuid) to anon,authenticated;

create or replace function public.generate_inventory_locations(p_prefix text,p_unit_start int,p_unit_end int,p_level_start text,p_level_end text,p_position_start int,p_position_end int)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_ctx record; u int; l int; p int; ls int; le int; total int; created int:=0; skipped int:=0; addr text; prefix text:=btrim(coalesce(p_prefix,''));
begin
 select * into v_ctx from public.get_current_actor_context(); perform private.inventory_assert_access(v_ctx.workspace_id,'admin');
 if length(prefix)<2 or length(prefix)>40 or p_unit_start<1 or p_unit_end<p_unit_start or p_position_start<1 or p_position_end<p_position_start or coalesce(p_level_start,'')!~'^[A-Za-z]$' or coalesce(p_level_end,'')!~'^[A-Za-z]$' then raise exception 'Intervalos de enderecos invalidos.'; end if;
 ls:=ascii(upper(p_level_start)); le:=ascii(upper(p_level_end)); if le<ls then raise exception 'A prateleira final deve vir depois da inicial.'; end if;
 total:=(p_unit_end-p_unit_start+1)*(le-ls+1)*(p_position_end-p_position_start+1); if total>250 then raise exception 'Gere no maximo 250 posicoes por vez.'; end if;
 for u in p_unit_start..p_unit_end loop for l in ls..le loop for p in p_position_start..p_position_end loop
  addr:=concat(prefix,' ',u,' · ',chr(l),' · ',p);
  if exists(select 1 from public.inventory_locations x where x.workspace_id=v_ctx.workspace_id and x.active and lower(x.normalized_address)=lower(addr)) then skipped:=skipped+1;
  else insert into public.inventory_locations(workspace_id,name,normalized_address,address_components) values(v_ctx.workspace_id,addr,addr,jsonb_build_object('estante',u,'prateleira',chr(l),'posicao',p)); created:=created+1; end if;
 end loop; end loop; end loop;
 return jsonb_build_object('created',created,'skipped',skipped);
end;$$;
revoke all on function public.generate_inventory_locations(text,int,int,text,text,int,int) from public;
grant execute on function public.generate_inventory_locations(text,int,int,text,text,int,int) to anon,authenticated;

create or replace function public.manage_inventory_location(p_location_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_ctx record; loc public.inventory_locations%rowtype;
begin
 select * into v_ctx from public.get_current_actor_context(); perform private.inventory_assert_access(v_ctx.workspace_id,'admin');
 select * into loc from public.inventory_locations l where l.workspace_id=v_ctx.workspace_id and l.id=p_location_id for update; if not found then raise exception 'Localizacao nao encontrada.'; end if;
 if p_action='activate' then update public.inventory_locations set active=true,updated_at=now() where id=loc.id;
 elsif p_action='archive' then
  if exists(select 1 from public.inventory_balances b where b.workspace_id=v_ctx.workspace_id and b.location_id=loc.id and (b.physical_quantity>0 or b.reserved_quantity>0)) or exists(select 1 from public.inventory_items i where i.workspace_id=v_ctx.workspace_id and i.default_location_id=loc.id and i.active) then raise exception 'Esvazie o local e remova-o dos itens antes de arquivar.'; end if;
  update public.inventory_locations set active=false,updated_at=now() where id=loc.id;
 elsif p_action='delete' then
  if exists(select 1 from public.inventory_balances b where b.workspace_id=v_ctx.workspace_id and b.location_id=loc.id) or exists(select 1 from public.inventory_movements m where m.workspace_id=v_ctx.workspace_id and (m.location_id=loc.id or m.counterpart_location_id=loc.id)) or exists(select 1 from public.inventory_reservations r where r.workspace_id=v_ctx.workspace_id and r.location_id=loc.id) or exists(select 1 from public.inventory_items i where i.workspace_id=v_ctx.workspace_id and i.default_location_id=loc.id) then raise exception 'Este local possui saldo, vinculos ou historico. Arquive-o.'; end if;
  delete from public.inventory_locations where id=loc.id;
 else raise exception 'Acao invalida.'; end if;
 return jsonb_build_object('success',true);
end;$$;
revoke all on function public.manage_inventory_location(uuid,text) from public;
grant execute on function public.manage_inventory_location(uuid,text) to anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('inventory_images','inventory_images',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists aida_inventory_images_select on storage.objects;
drop policy if exists aida_inventory_images_insert on storage.objects;
drop policy if exists aida_inventory_images_update on storage.objects;
drop policy if exists aida_inventory_images_delete on storage.objects;
create policy aida_inventory_images_select on storage.objects for select to anon,authenticated using(bucket_id='inventory_images' and (storage.foldername(name))[1]=(select workspace_id::text from public.get_current_actor_context()) and (select is_admin or is_attendant or is_technician from public.get_current_actor_context()));
create policy aida_inventory_images_insert on storage.objects for insert to anon,authenticated with check(bucket_id='inventory_images' and (storage.foldername(name))[1]=(select workspace_id::text from public.get_current_actor_context()) and (storage.foldername(name))[2]='inventory' and (select is_admin from public.get_current_actor_context()));
create policy aida_inventory_images_update on storage.objects for update to anon,authenticated using(bucket_id='inventory_images' and (storage.foldername(name))[1]=(select workspace_id::text from public.get_current_actor_context()) and (select is_admin from public.get_current_actor_context())) with check(bucket_id='inventory_images' and (storage.foldername(name))[1]=(select workspace_id::text from public.get_current_actor_context()) and (select is_admin from public.get_current_actor_context()));
create policy aida_inventory_images_delete on storage.objects for delete to anon,authenticated using(bucket_id='inventory_images' and (storage.foldername(name))[1]=(select workspace_id::text from public.get_current_actor_context()) and (select is_admin from public.get_current_actor_context()));

commit;
