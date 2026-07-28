-- Deve ser executada depois de inventory_operations.sql.
-- Completa o cadastro com codigo universal, observacoes e imagem.
begin;

create or replace function public.save_inventory_item(p_item jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_id uuid;
    v_unit text;
    v_allow_decimal boolean;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_item is null or jsonb_typeof(p_item) <> 'object'
       or length(btrim(coalesce(p_item ->> 'name', ''))) < 2 then
        raise exception 'Informe um nome com pelo menos 2 caracteres.';
    end if;
    v_id := nullif(p_item ->> 'id', '')::uuid;
    v_unit := coalesce(nullif(p_item ->> 'unit_code', ''), 'un');
    v_allow_decimal := coalesce((p_item ->> 'allow_decimal')::boolean, false);

    if v_id is null then
        insert into public.inventory_items(
            workspace_id, name, sku, universal_code, category, brand,
            description, internal_notes, image_url, unit_code,
            custom_unit_name, allow_decimal, track_stock,
            minimum_quantity, ideal_quantity, default_location_id
        ) values (
            v_ctx.workspace_id, btrim(p_item ->> 'name'),
            nullif(btrim(p_item ->> 'sku'), ''),
            nullif(btrim(p_item ->> 'universal_code'), ''),
            nullif(btrim(p_item ->> 'category'), ''),
            nullif(btrim(p_item ->> 'brand'), ''),
            nullif(btrim(p_item ->> 'description'), ''),
            nullif(btrim(p_item ->> 'internal_notes'), ''),
            nullif(btrim(p_item ->> 'image_url'), ''),
            v_unit, nullif(btrim(p_item ->> 'custom_unit_name'), ''),
            v_allow_decimal, coalesce((p_item ->> 'track_stock')::boolean, true),
            coalesce((p_item ->> 'minimum_quantity')::numeric, 0),
            coalesce((p_item ->> 'ideal_quantity')::numeric, 0),
            nullif(p_item ->> 'default_location_id', '')::uuid
        ) returning id into v_id;
        insert into public.inventory_item_costs(item_id, workspace_id)
        values (v_id, v_ctx.workspace_id);
    else
        update public.inventory_items i
        set name = btrim(p_item ->> 'name'),
            sku = nullif(btrim(p_item ->> 'sku'), ''),
            universal_code = nullif(btrim(p_item ->> 'universal_code'), ''),
            category = nullif(btrim(p_item ->> 'category'), ''),
            brand = nullif(btrim(p_item ->> 'brand'), ''),
            description = nullif(btrim(p_item ->> 'description'), ''),
            internal_notes = nullif(btrim(p_item ->> 'internal_notes'), ''),
            image_url = nullif(btrim(p_item ->> 'image_url'), ''),
            unit_code = v_unit,
            custom_unit_name = nullif(btrim(p_item ->> 'custom_unit_name'), ''),
            allow_decimal = v_allow_decimal,
            track_stock = coalesce((p_item ->> 'track_stock')::boolean, true),
            minimum_quantity = coalesce((p_item ->> 'minimum_quantity')::numeric, 0),
            ideal_quantity = coalesce((p_item ->> 'ideal_quantity')::numeric, 0),
            default_location_id = nullif(p_item ->> 'default_location_id', '')::uuid,
            active = coalesce((p_item ->> 'active')::boolean, i.active),
            updated_at = now()
        where i.workspace_id = v_ctx.workspace_id and i.id = v_id;
        if not found then raise exception 'Item nao encontrado.'; end if;
    end if;
    return v_id;
end;
$$;

revoke all on function public.save_inventory_item(jsonb) from public;
grant execute on function public.save_inventory_item(jsonb) to anon, authenticated;

commit;
