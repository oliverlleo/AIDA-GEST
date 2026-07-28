begin;

create or replace function public.manage_inventory_location_scheme(
    p_scheme_id uuid,
    p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_scheme public.inventory_location_schemes%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');

    select * into v_scheme
    from public.inventory_location_schemes s
    where s.workspace_id = v_ctx.workspace_id
      and s.id = p_scheme_id
    for update;

    if not found then
        raise exception 'Padrao de localizacao nao encontrado.';
    end if;

    if p_action = 'activate' then
        update public.inventory_location_schemes
        set active = true, updated_at = now()
        where workspace_id = v_ctx.workspace_id and id = v_scheme.id;
    elsif p_action = 'archive' then
        update public.inventory_location_schemes
        set active = false, updated_at = now()
        where workspace_id = v_ctx.workspace_id and id = v_scheme.id;
    elsif p_action = 'delete' then
        if exists (
            select 1
            from public.inventory_locations l
            where l.workspace_id = v_ctx.workspace_id
              and l.scheme_id = v_scheme.id
        ) then
            raise exception 'Este padrao possui enderecos vinculados. Arquive-o para preservar o historico.';
        end if;

        delete from public.inventory_location_schemes
        where workspace_id = v_ctx.workspace_id and id = v_scheme.id;
    else
        raise exception 'Acao invalida.';
    end if;

    return jsonb_build_object('success', true, 'action', p_action);
end;
$$;

revoke all on function public.manage_inventory_location_scheme(uuid, text) from public;
grant execute on function public.manage_inventory_location_scheme(uuid, text) to anon, authenticated;

commit;