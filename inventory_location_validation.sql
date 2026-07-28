-- Validacao de enderecos estruturados sem expor expressoes regulares ao usuario.
begin;

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
    v_scheme_id uuid;
    v_scheme public.inventory_location_schemes%rowtype;
    v_components jsonb;
    v_part jsonb;
    v_key text;
    v_type text;
    v_value text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');
    if p_location is null or jsonb_typeof(p_location) <> 'object' then
        raise exception 'Dados da localizacao invalidos.';
    end if;
    v_id := nullif(p_location ->> 'id', '')::uuid;
    v_name := btrim(coalesce(p_location ->> 'name', ''));
    v_scheme_id := nullif(p_location ->> 'scheme_id', '')::uuid;
    v_components := coalesce(p_location -> 'address_components', '{}'::jsonb);
    if length(v_name) < 2 or jsonb_typeof(v_components) <> 'object' then
        raise exception 'Informe um nome e um endereco validos.';
    end if;

    if v_scheme_id is not null then
        select * into v_scheme
        from public.inventory_location_schemes s
        where s.workspace_id = v_ctx.workspace_id and s.id = v_scheme_id and s.active;
        if not found then raise exception 'Padrao de endereco nao encontrado.'; end if;
    end if;

    if v_scheme_id is not null and v_scheme.mode = 'structured' then
        v_normalized := '';
        for v_part in select value from jsonb_array_elements(v_scheme.component_labels)
        loop
            v_type := v_part ->> 'type';
            v_key := nullif(btrim(v_part ->> 'label'), '');
            if v_type in ('fixed', 'separator') then
                v_value := coalesce(v_part ->> 'value', '');
            else
                if v_key is null then raise exception 'O padrao possui uma parte sem nome.'; end if;
                v_value := btrim(coalesce(v_components ->> v_key, ''));
                if v_value = '' then raise exception 'Preencha a parte % do endereco.', v_key; end if;
                if v_type = 'letters' and v_value !~ '^[[:alpha:]]+$' then
                    raise exception '% aceita somente letras.', v_key;
                elsif v_type = 'numbers' and v_value !~ '^[0-9]+$' then
                    raise exception '% aceita somente numeros.', v_key;
                elsif v_type = 'alphanumeric' and v_value !~ '^[[:alnum:]]+$' then
                    raise exception '% aceita somente letras e numeros.', v_key;
                elsif v_type = 'options' and not exists (
                    select 1 from jsonb_array_elements_text(coalesce(v_part -> 'options', '[]'::jsonb)) o
                    where o = v_value
                ) then
                    raise exception 'Escolha uma opcao valida para %.', v_key;
                end if;
            end if;
            v_normalized := v_normalized || v_value;
        end loop;
        v_normalized := lower(btrim(v_normalized));
    else
        v_normalized := lower(regexp_replace(
            btrim(coalesce(p_location ->> 'normalized_address', v_name)),
            '\s+', ' ', 'g'
        ));
    end if;
    if length(v_normalized) < 2 then raise exception 'Endereco invalido.'; end if;

    if v_id is null then
        insert into public.inventory_locations(
            workspace_id, scheme_id, name, address_components, normalized_address
        ) values (
            v_ctx.workspace_id, v_scheme_id, v_name, v_components, v_normalized
        ) returning id into v_id;
    else
        update public.inventory_locations l
        set scheme_id = v_scheme_id,
            name = v_name,
            address_components = v_components,
            normalized_address = v_normalized,
            updated_at = now()
        where l.workspace_id = v_ctx.workspace_id and l.id = v_id;
        if not found then raise exception 'Localizacao nao encontrada.'; end if;
    end if;
    return v_id;
end;
$$;

revoke all on function public.save_inventory_location(jsonb) from public;
grant execute on function public.save_inventory_location(jsonb) to anon, authenticated;

commit;
