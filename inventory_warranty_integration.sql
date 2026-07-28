-- Integra a decisao de garantia ao mesmo catalogo/reserva/compra do estoque.
begin;

create or replace function public.complete_warranty_analysis_with_inventory(
    p_ticket_id uuid,
    p_report text,
    p_tech_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_parts text;
    v_updated jsonb;
    v_allocation jsonb;
    v_route text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    select * into v_ticket
    from public.tickets t
    where t.workspace_id = v_ctx.workspace_id
      and t.id = p_ticket_id
      and t.deleted_at is null
    for update;
    if not found or not v_ticket.warranty_claim
       or v_ticket.warranty_status <> 'pending'
       or v_ticket.status <> 'Analise Tecnica' then
        raise exception 'Este retorno nao esta aguardando a decisao da garantia.';
    end if;
    if not (
        v_ctx.is_admin
        or (
            v_ctx.is_technician
            and v_ticket.technician_id = v_ctx.actor_employee_id
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a garantia.';
    end if;

    select string_agg(
        format('%s x %s', tp.requested_quantity, tp.requested_name_snapshot),
        ', ' order by tp.created_at, tp.id
    ) into v_parts
    from public.ticket_part_items tp
    where tp.workspace_id = v_ctx.workspace_id
      and tp.ticket_id = p_ticket_id
      and tp.request_stage = 'warranty'
      and tp.status not in ('cancelled', 'released', 'consumed');
    if nullif(btrim(coalesce(v_parts, '')), '') is null then
        raise exception 'Selecione as pecas necessarias para a garantia.';
    end if;

    v_updated := public.complete_warranty_analysis(
        p_ticket_id,
        true,
        p_report,
        true,
        v_parts,
        p_tech_notes
    );
    v_allocation := private.inventory_allocate_ticket_parts(v_ctx.workspace_id, p_ticket_id);
    v_route := case
        when coalesce((v_allocation ->> 'fully_reserved')::boolean, false)
            then 'repair'
        else 'purchase'
    end;

    update public.tickets t
    set status = case when v_route = 'repair' then 'Andamento Reparo' else 'Compra Peca' end,
        budget_status = 'Aprovado',
        parts_status = case when v_route = 'repair' then 'Reservado' else 'Pendente' end,
        updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_ticket_id
    returning to_jsonb(t.*) into v_updated;

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        case when v_route = 'repair'
            then 'Reservou Pecas da Garantia'
            else 'Encaminhou Garantia para Compra'
        end,
        format(
            'A garantia da **OS %s** foi confirmada por **%s**. %s',
            coalesce(v_ticket.os_number, 'nao informada'),
            v_ctx.actor_name,
            case when v_route = 'repair'
                then 'Todas as pecas foram reservadas e a OS seguiu para **Reparo**.'
                else 'O saldo disponivel foi reservado e somente a falta seguiu para **Compra de Pecas**.'
            end
        ),
        v_ctx.actor_name
    );

    return v_updated || jsonb_build_object(
        'route', v_route,
        'missing_quantity', coalesce((v_allocation ->> 'missing_quantity')::numeric, 0),
        'shortages', coalesce(v_allocation -> 'shortages', '[]'::jsonb)
    );
end;
$$;

revoke all on function public.complete_warranty_analysis_with_inventory(uuid, text, text)
from public;
grant execute on function public.complete_warranty_analysis_with_inventory(uuid, text, text)
to anon, authenticated;

commit;
