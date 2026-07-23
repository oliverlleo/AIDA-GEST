-- ATENCAO: este rollback remove o cadastro de clientes e seus dados.
-- As OS permanecem intactas com os snapshots client_name/contact_info.

begin;

drop function if exists public.get_customer_page(text, integer, jsonb, boolean);
drop function if exists public.get_customer_page(text, integer, jsonb);
drop function if exists public.get_customer_ticket_page(uuid, text, integer, jsonb, boolean);
drop function if exists public.get_customer_ticket_page(uuid, text, integer, jsonb);
drop function if exists public.save_customer(jsonb);

drop trigger if exists aida_enforce_ticket_customer_link on public.tickets;
drop function if exists public.aida_enforce_ticket_customer_link();

alter table public.tickets
    drop constraint if exists tickets_workspace_customer_fkey;
drop index if exists public.tickets_workspace_customer_created_idx;
alter table public.tickets
    drop column if exists customer_id;

drop trigger if exists aida_enforce_customer_identity on public.customers;
drop function if exists public.aida_enforce_customer_identity();
drop table if exists public.customers;
drop function if exists public.aida_customers_enabled();

-- Restaura o normalizador anterior. A chave modules.customers que ja estiver
-- salva e inofensiva para versoes sem o modulo e nao exige reescrita de config.
create or replace function public.update_workspace_tracker_config(p_config jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_ctx record;
    v_config jsonb;
    v_customization jsonb;
    v_modes jsonb;
    v_value text;
    v_key text;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not coalesce(v_ctx.is_admin, false) then
        raise exception 'Acesso negado: somente administradores podem alterar o gerenciamento.';
    end if;
    if p_config is null or jsonb_typeof(p_config) <> 'object' then
        raise exception 'Configuracao invalida.';
    end if;

    v_customization := coalesce(p_config -> 'customization', '{}'::jsonb);
    if jsonb_typeof(v_customization) <> 'object' then
        raise exception 'Configuracao dos seletores invalida.';
    end if;

    foreach v_key in array array['workflow', 'modules', 'ticket_fields', 'overview']
    loop
        if v_customization -> v_key is not null
           and jsonb_typeof(v_customization -> v_key) <> 'boolean' then
            raise exception 'O seletor % deve ser verdadeiro ou falso.', v_key;
        end if;
    end loop;

    v_customization := jsonb_build_object(
        'workflow', lower(coalesce(v_customization ->> 'workflow', 'false')) = 'true',
        'modules', lower(coalesce(v_customization ->> 'modules', 'false')) = 'true',
        'ticket_fields', lower(coalesce(v_customization ->> 'ticket_fields', 'false')) = 'true',
        'overview', lower(coalesce(v_customization ->> 'overview', 'false')) = 'true'
    );
    v_config := jsonb_set(p_config, '{customization}', v_customization, true);

    if not (v_customization ->> 'workflow')::boolean then
        v_config := jsonb_set(
            v_config,
            '{workflow}',
            coalesce(v_config -> 'workflow', '{}'::jsonb) || jsonb_build_object(
                'parts_control', true,
                'analysis_timer', true,
                'repair_timer', true,
                'delivery_mode', 'complete',
                'priority_requests', true
            ),
            true
        );
    end if;

    if not (v_customization ->> 'modules')::boolean then
        v_config := jsonb_set(v_config, '{modules}', jsonb_build_object(
            'agenda', true,
            'suppliers', true,
            'manager_dashboard', true,
            'public_tracker', true
        ), true);
    end if;

    if not (v_customization ->> 'ticket_fields')::boolean then
        v_config := jsonb_set(v_config, '{ticket_field_modes}', jsonb_build_object(
            'client_name', 'required',
            'contact_info', 'optional',
            'os_number', 'required',
            'serial_number', 'optional',
            'priority', 'optional',
            'device_model', 'required',
            'analysis_deadline', 'required',
            'deadline', 'required',
            'device_condition', 'optional',
            'responsible', 'required',
            'defect_reported', 'required',
            'checklist_entry', 'optional',
            'checklist_exit', 'optional',
            'photos', 'optional',
            'analysis_schedule', 'optional',
            'repair_schedule', 'optional'
        ), true);
    end if;

    if not (v_customization ->> 'overview')::boolean then
        v_config := jsonb_set(v_config, '{overview_sections}', jsonb_build_object(
            'awaiting_start', true,
            'awaiting_budget', true,
            'parts_purchase', true,
            'parts_receipt', true,
            'tests', true,
            'pickup', true,
            'overdue', true,
            'unscheduled', true,
            'priority', true
        ), true);
    end if;

    if jsonb_typeof(coalesce(v_config -> 'workflow', '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(v_config -> 'modules', '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(v_config -> 'overview_sections', '{}'::jsonb)) <> 'object' then
        raise exception 'Configuracao de gerenciamento invalida.';
    end if;

    v_modes := coalesce(v_config -> 'ticket_field_modes', '{}'::jsonb);
    if jsonb_typeof(v_modes) <> 'object' then
        raise exception 'Configuracao de campos invalida.';
    end if;

    for v_value in select value #>> '{}' from jsonb_each(v_modes)
    loop
        if v_value not in ('disabled', 'optional', 'required') then
            raise exception 'Modo de campo invalido: %.', v_value;
        end if;
    end loop;

    if coalesce(v_config -> 'workflow' ->> 'delivery_mode', 'complete') not in ('complete', 'simple') then
        raise exception 'Modo de retirada/entrega invalido.';
    end if;

    if not public.aida_config_bool(v_config, 'workflow', 'parts_control', true)
       and exists (
            select 1
              from public.tickets t
             where t.workspace_id = v_ctx.workspace_id
               and t.deleted_at is null
               and (
                    t.status = 'Compra Peca'
                    or t.repair_paused_at is not null
                    or (t.parts_status in ('Pendente', 'Comprado') and t.status <> 'Finalizado')
               )
       ) then
        raise exception 'Nao e possivel desativar Compra de Pecas: existem OS em compra ou reparos pausados. Conclua essas OS primeiro.';
    end if;

    v_config := jsonb_set(
        v_config,
        '{ticket_field_modes}',
        v_modes || jsonb_build_object(
            'client_name', 'required',
            'os_number', 'required',
            'device_model', 'required'
        ),
        true
    );

    update public.workspaces
       set tracker_config = v_config
     where id = v_ctx.workspace_id;

    if not found then
        raise exception 'Workspace nao encontrado.';
    end if;
end;
$$;

revoke all on function public.update_workspace_tracker_config(jsonb) from public;
grant execute on function public.update_workspace_tracker_config(jsonb) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
