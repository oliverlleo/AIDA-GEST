begin;

create table if not exists public.inventory_location_groups (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete restrict,
    name text not null,
    kind text not null default 'shelf',
    description text,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_location_groups_name_check check (char_length(btrim(name)) between 2 and 80),
    constraint inventory_location_groups_kind_check check (kind in ('shelf', 'cabinet', 'drawer', 'room', 'other')),
    constraint inventory_location_groups_description_check check (description is null or char_length(description) <= 300),
    unique (workspace_id, id)
);

create unique index if not exists inventory_location_groups_workspace_name_uq
    on public.inventory_location_groups(workspace_id, lower(btrim(name)))
    where active;
create index if not exists inventory_location_groups_workspace_active_idx
    on public.inventory_location_groups(workspace_id, active desc, lower(name), id);

alter table public.inventory_location_groups enable row level security;
revoke all on table public.inventory_location_groups from public, anon, authenticated;

alter table public.inventory_locations
    add column if not exists group_id uuid,
    add column if not exists system_type text;

alter table public.inventory_locations
    drop constraint if exists inventory_locations_system_type_check;
alter table public.inventory_locations
    add constraint inventory_locations_system_type_check
    check (system_type is null or system_type in ('direct_ticket'));

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'inventory_locations_group_fkey'
          and conrelid = 'public.inventory_locations'::regclass
    ) then
        alter table public.inventory_locations
            add constraint inventory_locations_group_fkey
            foreign key (workspace_id, group_id)
            references public.inventory_location_groups(workspace_id, id)
            on delete restrict;
    end if;
end;
$$;

create index if not exists inventory_locations_workspace_group_idx
    on public.inventory_locations(workspace_id, group_id, active desc, lower(name), id);

-- Endereços anteriores continuam válidos e passam a aparecer em um agrupador próprio.
insert into public.inventory_location_groups(workspace_id, name, kind, description)
select distinct l.workspace_id, 'Locais existentes', 'other',
       'Endereços preservados da organização anterior do estoque.'
from public.inventory_locations l
where l.group_id is null and l.system_type is null
  and not exists (
      select 1 from public.inventory_location_groups g
      where g.workspace_id = l.workspace_id and lower(g.name) = 'locais existentes'
  );

update public.inventory_locations l
set group_id = g.id,
    updated_at = now()
from public.inventory_location_groups g
where l.group_id is null and l.system_type is null
  and g.workspace_id = l.workspace_id
  and lower(g.name) = 'locais existentes';

create or replace function public.save_inventory_location_group(p_group jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_id uuid;
    v_name text;
    v_kind text;
    v_description text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_group is null or jsonb_typeof(p_group) <> 'object' then
        raise exception 'Dados do organizador invalidos.';
    end if;

    begin
        v_id := nullif(p_group ->> 'id', '')::uuid;
    exception when others then
        raise exception 'Organizador invalido.';
    end;
    v_name := btrim(coalesce(p_group ->> 'name', ''));
    v_kind := coalesce(nullif(p_group ->> 'kind', ''), 'shelf');
    v_description := nullif(btrim(coalesce(p_group ->> 'description', '')), '');

    if char_length(v_name) < 2 or char_length(v_name) > 80 then
        raise exception 'Informe um nome entre 2 e 80 caracteres.';
    end if;
    if v_kind not in ('shelf', 'cabinet', 'drawer', 'room', 'other') then
        raise exception 'Escolha um tipo de organizador valido.';
    end if;
    if char_length(coalesce(v_description, '')) > 300 then
        raise exception 'A descricao deve ter no maximo 300 caracteres.';
    end if;
    if exists (
        select 1 from public.inventory_location_groups g
        where g.workspace_id = v_ctx.workspace_id
          and g.active
          and lower(btrim(g.name)) = lower(v_name)
          and (v_id is null or g.id <> v_id)
    ) then
        raise exception 'Ja existe um organizador ativo com este nome.';
    end if;

    if v_id is null then
        insert into public.inventory_location_groups(workspace_id, name, kind, description)
        values (v_ctx.workspace_id, v_name, v_kind, v_description)
        returning id into v_id;
    else
        update public.inventory_location_groups g
        set name = v_name,
            kind = v_kind,
            description = v_description,
            updated_at = now()
        where g.workspace_id = v_ctx.workspace_id and g.id = v_id;
        if not found then raise exception 'Organizador nao encontrado.'; end if;

        update public.inventory_locations l
        set normalized_address = lower(v_name || ' · ' || l.name),
            updated_at = now()
        where l.workspace_id = v_ctx.workspace_id and l.group_id = v_id;
    end if;

    return v_id;
end;
$$;
revoke all on function public.save_inventory_location_group(jsonb) from public;
grant execute on function public.save_inventory_location_group(jsonb) to anon, authenticated;

create or replace function public.manage_inventory_location_group(p_group_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_group public.inventory_location_groups%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    select * into v_group
    from public.inventory_location_groups g
    where g.workspace_id = v_ctx.workspace_id and g.id = p_group_id
    for update;
    if not found then raise exception 'Organizador nao encontrado.'; end if;

    if p_action = 'activate' then
        if exists (
            select 1 from public.inventory_location_groups g
            where g.workspace_id = v_ctx.workspace_id and g.active
              and lower(btrim(g.name)) = lower(btrim(v_group.name)) and g.id <> v_group.id
        ) then raise exception 'Ja existe um organizador ativo com este nome.'; end if;
        update public.inventory_location_groups set active = true, updated_at = now()
        where workspace_id = v_ctx.workspace_id and id = v_group.id;
    elsif p_action = 'archive' then
        if exists (
            select 1 from public.inventory_balances b
            join public.inventory_locations l
              on l.workspace_id = b.workspace_id and l.id = b.location_id
            where l.workspace_id = v_ctx.workspace_id and l.group_id = v_group.id
              and (b.physical_quantity > 0 or b.reserved_quantity > 0)
        ) then
            raise exception 'Esvazie os enderecos deste organizador antes de arquivar.';
        end if;
        update public.inventory_location_groups set active = false, updated_at = now()
        where workspace_id = v_ctx.workspace_id and id = v_group.id;
    elsif p_action = 'delete' then
        if exists (
            select 1 from public.inventory_locations l
            where l.workspace_id = v_ctx.workspace_id and l.group_id = v_group.id
        ) then
            raise exception 'Exclua ou mova os enderecos internos antes de excluir o organizador.';
        end if;
        delete from public.inventory_location_groups
        where workspace_id = v_ctx.workspace_id and id = v_group.id;
    else
        raise exception 'Acao invalida.';
    end if;

    return jsonb_build_object('success', true, 'action', p_action);
end;
$$;
revoke all on function public.manage_inventory_location_group(uuid, text) from public;
grant execute on function public.manage_inventory_location_group(uuid, text) to anon, authenticated;

create or replace function public.save_inventory_location(p_location jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_id uuid;
    v_name text;
    v_normalized text;
    v_group_id uuid;
    v_group public.inventory_location_groups%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_location is null or jsonb_typeof(p_location) <> 'object' then
        raise exception 'Dados do endereco invalidos.';
    end if;
    begin
        v_id := nullif(p_location ->> 'id', '')::uuid;
        v_group_id := nullif(p_location ->> 'group_id', '')::uuid;
    exception when others then
        raise exception 'Endereco invalido.';
    end;
    v_name := btrim(coalesce(p_location ->> 'name', ''));
    if char_length(v_name) < 1 or char_length(v_name) > 80 then
        raise exception 'Informe o nome do endereco interno.';
    end if;
    if v_group_id is null then
        raise exception 'Escolha a estante, armario ou area deste endereco.';
    end if;

    select * into v_group
    from public.inventory_location_groups g
    where g.workspace_id = v_ctx.workspace_id and g.id = v_group_id and g.active;
    if not found then raise exception 'Organizador nao encontrado ou arquivado.'; end if;

    v_normalized := lower(v_group.name || ' · ' || v_name);
    if exists (
        select 1 from public.inventory_locations l
        where l.workspace_id = v_ctx.workspace_id and l.active
          and lower(l.normalized_address) = v_normalized
          and (v_id is null or l.id <> v_id)
    ) then raise exception 'Este endereco ja existe neste organizador.'; end if;

    if v_id is null then
        insert into public.inventory_locations(
            workspace_id, group_id, name, normalized_address, address_components
        ) values (
            v_ctx.workspace_id, v_group_id, v_name, v_normalized,
            jsonb_build_object('group_kind', v_group.kind)
        ) returning id into v_id;
    else
        update public.inventory_locations l
        set group_id = v_group_id,
            scheme_id = null,
            name = v_name,
            normalized_address = v_normalized,
            address_components = jsonb_build_object('group_kind', v_group.kind),
            updated_at = now()
        where l.workspace_id = v_ctx.workspace_id and l.id = v_id;
        if not found then raise exception 'Endereco nao encontrado.'; end if;
    end if;
    return v_id;
end;
$$;
revoke all on function public.save_inventory_location(jsonb) from public;
grant execute on function public.save_inventory_location(jsonb) to anon, authenticated;

create or replace function public.save_inventory_locations_batch(p_group_id uuid, p_names jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_group public.inventory_location_groups%rowtype;
    v_value jsonb;
    v_name text;
    v_normalized text;
    v_created integer := 0;
    v_skipped integer := 0;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_names is null or jsonb_typeof(p_names) <> 'array'
       or jsonb_array_length(p_names) < 1 or jsonb_array_length(p_names) > 50 then
        raise exception 'Informe entre 1 e 50 enderecos.';
    end if;
    select * into v_group
    from public.inventory_location_groups g
    where g.workspace_id = v_ctx.workspace_id and g.id = p_group_id and g.active;
    if not found then raise exception 'Organizador nao encontrado ou arquivado.'; end if;

    for v_value in select value from jsonb_array_elements(p_names)
    loop
        v_name := btrim(coalesce(v_value #>> '{}', ''));
        if char_length(v_name) < 1 or char_length(v_name) > 80 then
            raise exception 'Cada endereco deve ter entre 1 e 80 caracteres.';
        end if;
        v_normalized := lower(v_group.name || ' · ' || v_name);
        if exists (
            select 1 from public.inventory_locations l
            where l.workspace_id = v_ctx.workspace_id and l.active
              and lower(l.normalized_address) = v_normalized
        ) then
            v_skipped := v_skipped + 1;
        else
            insert into public.inventory_locations(
                workspace_id, group_id, name, normalized_address, address_components
            ) values (
                v_ctx.workspace_id, v_group.id, v_name, v_normalized,
                jsonb_build_object('group_kind', v_group.kind)
            );
            v_created := v_created + 1;
        end if;
    end loop;

    return jsonb_build_object('success', true, 'created', v_created, 'skipped', v_skipped);
end;
$$;
revoke all on function public.save_inventory_locations_batch(uuid, jsonb) from public;
grant execute on function public.save_inventory_locations_batch(uuid, jsonb) to anon, authenticated;

create or replace function public.get_inventory_locations()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    return jsonb_build_object(
        'groups', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', g.id,
                'name', g.name,
                'kind', g.kind,
                'description', g.description,
                'active', g.active,
                'location_count', (select count(*) from public.inventory_locations l where l.workspace_id=g.workspace_id and l.group_id=g.id),
                'active_location_count', (select count(*) from public.inventory_locations l where l.workspace_id=g.workspace_id and l.group_id=g.id and l.active),
                'linked_item_count', (select count(distinct b.item_id) from public.inventory_balances b join public.inventory_locations l on l.workspace_id=b.workspace_id and l.id=b.location_id where l.workspace_id=g.workspace_id and l.group_id=g.id),
                'physical_quantity', coalesce((select sum(b.physical_quantity) from public.inventory_balances b join public.inventory_locations l on l.workspace_id=b.workspace_id and l.id=b.location_id where l.workspace_id=g.workspace_id and l.group_id=g.id),0),
                'reserved_quantity', coalesce((select sum(b.reserved_quantity) from public.inventory_balances b join public.inventory_locations l on l.workspace_id=b.workspace_id and l.id=b.location_id where l.workspace_id=g.workspace_id and l.group_id=g.id),0)
            ) order by g.active desc, lower(g.name), g.id)
            from public.inventory_location_groups g
            where g.workspace_id = v_ctx.workspace_id
        ), '[]'::jsonb),
        'locations', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', l.id,
                'group_id', l.group_id,
                'group_name', g.name,
                'group_kind', g.kind,
                'group_active', coalesce(g.active, true),
                'name', l.name,
                'normalized_address', l.normalized_address,
                'display_address', case when g.id is null then l.normalized_address else g.name || ' · ' || l.name end,
                'active', l.active and coalesce(g.active, true),
                'own_active', l.active,
                'linked_item_count', (select count(*) from public.inventory_balances b where b.workspace_id=l.workspace_id and b.location_id=l.id),
                'physical_quantity', coalesce((select sum(b.physical_quantity) from public.inventory_balances b where b.workspace_id=l.workspace_id and b.location_id=l.id),0),
                'reserved_quantity', coalesce((select sum(b.reserved_quantity) from public.inventory_balances b where b.workspace_id=l.workspace_id and b.location_id=l.id),0),
                'movement_count', (select count(*) from public.inventory_movements m where m.workspace_id=l.workspace_id and (m.location_id=l.id or m.counterpart_location_id=l.id))
            ) order by coalesce(g.active,true) desc, l.active desc, lower(coalesce(g.name,'')), lower(l.name), l.id)
            from public.inventory_locations l
            left join public.inventory_location_groups g
              on g.workspace_id = l.workspace_id and g.id = l.group_id
            where l.workspace_id = v_ctx.workspace_id
              and l.system_type is null
        ), '[]'::jsonb),
        'schemes', '[]'::jsonb
    );
end;
$$;
revoke all on function public.get_inventory_locations() from public;
grant execute on function public.get_inventory_locations() to anon, authenticated;

commit;