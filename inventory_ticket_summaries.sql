-- Resumo leve para cards. Recebe somente IDs da pagina ja carregada.
begin;

create or replace function public.get_ticket_inventory_summaries(p_ticket_ids uuid[])
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
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');
    if p_ticket_ids is null or cardinality(p_ticket_ids) = 0 then
        return '[]'::jsonb;
    end if;
    if cardinality(p_ticket_ids) > 100 then
        raise exception 'No maximo 100 OS podem ser consultadas por vez.';
    end if;

    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', t.id,
            'inventory_summary', jsonb_build_object(
                'item_count', coalesce(x.item_count, 0),
                'requested_quantity', coalesce(x.requested_quantity, 0),
                'reserved_quantity', coalesce(x.reserved_quantity, 0),
                'missing_quantity', greatest(0, coalesce(x.requested_quantity, 0) - coalesce(x.reserved_quantity, 0)),
                'consumed_quantity', coalesce(x.consumed_quantity, 0),
                'pending_purchase_count', coalesce(x.pending_purchase_count, 0)
            )
        ) order by t.id)
        from public.tickets t
        left join lateral (
            select count(*) item_count,
                   sum(tp.requested_quantity) requested_quantity,
                   sum(coalesce(r.reserved_quantity, 0)) reserved_quantity,
                   sum(coalesce(r.consumed_quantity, 0)) consumed_quantity,
                   count(*) filter (where tp.status in ('partial', 'purchase_pending')) pending_purchase_count
            from public.ticket_part_items tp
            left join lateral (
                select sum(ir.reserved_quantity - ir.consumed_quantity - ir.released_quantity) reserved_quantity,
                       sum(ir.consumed_quantity) consumed_quantity
                from public.inventory_reservations ir
                where ir.workspace_id = tp.workspace_id
                  and ir.ticket_part_item_id = tp.id
            ) r on true
            where tp.workspace_id = t.workspace_id
              and tp.ticket_id = t.id
              and tp.status <> 'cancelled'
        ) x on true
        where t.workspace_id = v_ctx.workspace_id
          and t.id = any(p_ticket_ids)
          and t.deleted_at is null
          and (
              not v_ctx.is_technician
              or v_ctx.is_admin
              or v_ctx.is_attendant
              or t.technician_id = v_ctx.actor_employee_id
          )
    ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_ticket_inventory_summaries(uuid[]) from public;
grant execute on function public.get_ticket_inventory_summaries(uuid[])
to anon, authenticated;

commit;
