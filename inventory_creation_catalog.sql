-- Catalogo leve para selecionar pecas durante a abertura de uma OS.
-- Prioriza compatibilidade com o modelo informado sem confiar no workspace do front-end.

begin;

create or replace function public.get_inventory_creation_catalog_page(
    p_device_model text default null,
    p_search text default null,
    p_limit integer default 20,
    p_cursor jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_device_model text := nullif(btrim(coalesce(p_device_model, '')), '');
    v_search text := nullif(btrim(coalesce(p_search, '')), '');
    v_cursor_name text;
    v_cursor_id uuid;
    v_cursor_compatible boolean;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if length(coalesce(v_device_model, '')) > 160 then
        raise exception 'O modelo deve ter no maximo 160 caracteres.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;
    if p_cursor is not null then
        begin
            v_cursor_name := p_cursor ->> 'name';
            v_cursor_id := (p_cursor ->> 'id')::uuid;
            v_cursor_compatible := (p_cursor ->> 'compatible')::boolean;
        exception when others then
            raise exception 'Cursor de catalogo invalido.';
        end;
    end if;

    with base as materialized (
        select
            i.id,
            i.name,
            i.sku,
            i.category,
            i.brand,
            i.unit_code,
            i.custom_unit_name,
            i.allow_decimal,
            i.track_stock,
            coalesce(b.physical, 0) physical_quantity,
            coalesce(b.reserved, 0) reserved_quantity,
            coalesce(b.available, 0) available_quantity,
            (
                select l.name
                from public.inventory_balances ib
                join public.inventory_locations l
                  on l.workspace_id = ib.workspace_id
                 and l.id = ib.location_id
                where ib.workspace_id = i.workspace_id
                  and ib.item_id = i.id
                  and ib.available_quantity > 0
                order by
                    case when l.id = i.default_location_id then 0 else 1 end,
                    l.normalized_address,
                    l.id
                limit 1
            ) primary_location,
            coalesce((
                select jsonb_agg(jsonb_build_object(
                    'id', alt.id,
                    'name', alt.name,
                    'sku', alt.sku,
                    'unit_code', alt.unit_code,
                    'allow_decimal', alt.allow_decimal,
                    'track_stock', alt.track_stock,
                    'relation_type', rel.relation_type,
                    'original_item_id', i.id,
                    'requested_original_name', i.name,
                    'available_quantity', coalesce(ab.available, 0),
                    'primary_location', ab.location_name
                ) order by rel.relation_type, lower(alt.name), alt.id)
                from public.inventory_item_relations rel
                join public.inventory_items alt
                  on alt.workspace_id = rel.workspace_id
                 and alt.id = rel.target_item_id
                left join lateral (
                    select
                        sum(ib.available_quantity) available,
                        min(l.name) filter (where ib.available_quantity > 0) location_name
                    from public.inventory_balances ib
                    join public.inventory_locations l
                      on l.workspace_id = ib.workspace_id
                     and l.id = ib.location_id
                    where ib.workspace_id = alt.workspace_id
                      and ib.item_id = alt.id
                ) ab on true
                where rel.workspace_id = i.workspace_id
                  and rel.source_item_id = i.id
                  and alt.active
            ), '[]'::jsonb) alternatives,
            (
                v_device_model is not null
                and exists (
                    select 1
                    from public.inventory_item_models im
                    join public.device_models dm
                      on dm.workspace_id = im.workspace_id
                     and dm.id = im.device_model_id
                    where im.workspace_id = i.workspace_id
                      and im.item_id = i.id
                      and lower(dm.name) = lower(v_device_model)
                )
            ) compatible_with_ticket,
            lower(i.name) sort_name
        from public.inventory_items i
        left join lateral (
            select
                sum(ib.physical_quantity) physical,
                sum(ib.reserved_quantity) reserved,
                sum(ib.available_quantity) available
            from public.inventory_balances ib
            where ib.workspace_id = i.workspace_id
              and ib.item_id = i.id
        ) b on true
        where i.workspace_id = v_ctx.workspace_id
          and i.active
          and (
              v_search is null
              or i.name ilike '%' || v_search || '%'
              or coalesce(i.sku, '') ilike '%' || v_search || '%'
              or coalesce(i.brand, '') ilike '%' || v_search || '%'
          )
    ), page_plus_one as materialized (
        select *
        from base b
        where p_cursor is null
           or (
                (case when b.compatible_with_ticket then 0 else 1 end, b.sort_name, b.id)
                >
                (case when v_cursor_compatible then 0 else 1 end, v_cursor_name, v_cursor_id)
           )
        order by compatible_with_ticket desc, sort_name, id
        limit p_limit + 1
    ), page_rows as materialized (
        select *
        from page_plus_one
        order by compatible_with_ticket desc, sort_name, id
        limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(
                to_jsonb(p) - 'sort_name'
                order by p.compatible_with_ticket desc, p.sort_name, p.id
            )
            from page_rows p
        ), '[]'::jsonb),
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (
            select jsonb_build_object(
                'compatible', p.compatible_with_ticket,
                'name', p.sort_name,
                'id', p.id
            )
            from page_rows p
            order by p.compatible_with_ticket asc, p.sort_name desc, p.id desc
            limit 1
        )
    )
    into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_inventory_creation_catalog_page(text, text, integer, jsonb)
from public;
grant execute on function public.get_inventory_creation_catalog_page(text, text, integer, jsonb)
to anon, authenticated;

commit;
