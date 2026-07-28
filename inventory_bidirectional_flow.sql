begin;

create or replace function private.inventory_convert_open_work_to_legacy(p_workspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket_ids uuid[] := '{}'::uuid[];
    v_ticket_id uuid;
    v_reservation record;
    v_remaining numeric(14,3);
    v_released integer := 0;
    v_cancelled_parts integer := 0;
    v_cancelled_purchases integer := 0;
begin
    select * into v_ctx from public.get_current_actor_context();
    if v_ctx.workspace_id is distinct from p_workspace_id or not coalesce(v_ctx.is_admin, false) then
        raise exception 'Somente um administrador da empresa pode desativar o Estoque.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_workspace_id::text, 0));

    select coalesce(array_agg(distinct affected.ticket_id), '{}'::uuid[])
      into v_ticket_ids
      from (
          select tp.ticket_id
            from public.ticket_part_items tp
           where tp.workspace_id = p_workspace_id
             and tp.status in ('needed', 'pending_approval', 'partial', 'purchase_pending', 'reserved', 'ready')
          union
          select tp.ticket_id
            from public.inventory_purchases p
            join public.inventory_purchase_items pi
              on pi.workspace_id = p.workspace_id and pi.purchase_id = p.id
            join public.inventory_purchase_allocations pa
              on pa.workspace_id = pi.workspace_id and pa.purchase_item_id = pi.id
            join public.ticket_part_items tp
              on tp.workspace_id = pa.workspace_id and tp.id = pa.ticket_part_item_id
           where p.workspace_id = p_workspace_id
             and p.status in ('draft', 'ordered', 'partial')
      ) affected;

    if cardinality(v_ticket_ids) = 0 then
        return jsonb_build_object(
            'success', true,
            'tickets_converted', 0,
            'reservations_released', 0,
            'parts_converted', 0,
            'purchases_archived', 0
        );
    end if;

    -- Antes de encerrar a estrutura do estoque, preserva a etapa simples que a OS deve exibir.
    update public.tickets t
       set parts_status = case
               when exists (
                   select 1
                     from public.inventory_purchases p
                     join public.inventory_purchase_items pi
                       on pi.workspace_id = p.workspace_id and pi.purchase_id = p.id
                     join public.inventory_purchase_allocations pa
                       on pa.workspace_id = pi.workspace_id and pa.purchase_item_id = pi.id
                     join public.ticket_part_items tp
                       on tp.workspace_id = pa.workspace_id and tp.id = pa.ticket_part_item_id
                    where p.workspace_id = p_workspace_id
                      and p.status in ('draft', 'ordered', 'partial')
                      and tp.ticket_id = t.id
               ) then 'Comprado'
               else 'Pendente'
           end,
           updated_at = now()
     where t.workspace_id = p_workspace_id
       and t.id = any(v_ticket_ids)
       and t.status = 'Compra Peca';

    -- Toda reserva aberta volta ao saldo disponível com movimento imutável de auditoria.
    for v_reservation in
        select r.*, tp.ticket_id
          from public.inventory_reservations r
          join public.ticket_part_items tp
            on tp.workspace_id = r.workspace_id and tp.id = r.ticket_part_item_id
         where r.workspace_id = p_workspace_id
           and r.status = 'active'
           and r.reserved_quantity > r.consumed_quantity + r.released_quantity
           and tp.ticket_id = any(v_ticket_ids)
         order by r.item_id, r.location_id, r.id
         for update of r
    loop
        v_remaining := v_reservation.reserved_quantity
            - v_reservation.consumed_quantity
            - v_reservation.released_quantity;

        perform 1
          from public.inventory_balances b
         where b.workspace_id = p_workspace_id
           and b.item_id = v_reservation.item_id
           and b.location_id = v_reservation.location_id
         for update;

        update public.inventory_balances
           set reserved_quantity = reserved_quantity - v_remaining,
               updated_at = now()
         where workspace_id = p_workspace_id
           and item_id = v_reservation.item_id
           and location_id = v_reservation.location_id
           and reserved_quantity >= v_remaining;
        if not found then
            raise exception 'Saldo reservado inconsistente. A desativacao do Estoque foi cancelada sem alterar dados.';
        end if;

        update public.inventory_reservations
           set released_quantity = released_quantity + v_remaining,
               status = 'released',
               updated_at = now()
         where workspace_id = p_workspace_id and id = v_reservation.id;

        insert into public.inventory_movements(
            workspace_id, item_id, location_id, movement_type,
            physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
            reason, actor_user_id, actor_employee_id, actor_name
        ) values (
            p_workspace_id, v_reservation.item_id, v_reservation.location_id, 'release',
            0, -v_remaining, v_reservation.ticket_id, v_reservation.ticket_part_item_id,
            'Reserva liberada automaticamente ao desativar o módulo de Estoque',
            v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
        );
        v_released := v_released + 1;
    end loop;

    update public.inventory_purchases p
       set status = 'cancelled',
           cancelled_at = now(),
           notes = pg_catalog.concat_ws(
               E'\n',
               nullif(p.notes, ''),
               pg_catalog.format(
                   '[Sistema] Controle transferido para o fluxo simples da OS ao desativar o Estoque por %s em %s.',
                   v_ctx.actor_name,
                   pg_catalog.to_char(now(), 'DD/MM/YYYY HH24:MI')
               )
           ),
           updated_at = now()
     where p.workspace_id = p_workspace_id
       and p.status in ('draft', 'ordered', 'partial')
       and exists (
           select 1
             from public.inventory_purchase_items pi
             join public.inventory_purchase_allocations pa
               on pa.workspace_id = pi.workspace_id and pa.purchase_item_id = pi.id
             join public.ticket_part_items tp
               on tp.workspace_id = pa.workspace_id and tp.id = pa.ticket_part_item_id
            where pi.workspace_id = p.workspace_id
              and pi.purchase_id = p.id
              and tp.ticket_id = any(v_ticket_ids)
       );
    get diagnostics v_cancelled_purchases = row_count;

    update public.ticket_part_items tp
       set status = 'cancelled',
           cancelled_at = now(),
           updated_at = now()
     where tp.workspace_id = p_workspace_id
       and tp.ticket_id = any(v_ticket_ids)
       and tp.status in ('needed', 'pending_approval', 'partial', 'purchase_pending', 'reserved', 'ready');
    get diagnostics v_cancelled_parts = row_count;

    foreach v_ticket_id in array v_ticket_ids
    loop
        insert into public.ticket_logs(ticket_id, action, details, user_name)
        select t.id,
               'Adaptou Controle de Peças',
               pg_catalog.format(
                   '**%s** desativou o módulo de Estoque. A **OS %s**, aparelho **%s** de **%s**, continuará no controle simples de compra de peças. Reservas abertas foram liberadas sem apagar o histórico.',
                   v_ctx.actor_name,
                   coalesce(t.os_number, 'não informada'),
                   coalesce(t.device_model, 'não informado'),
                   coalesce(t.client_name, 'não informado')
               ),
               v_ctx.actor_name
          from public.tickets t
         where t.workspace_id = p_workspace_id and t.id = v_ticket_id;
    end loop;

    return jsonb_build_object(
        'success', true,
        'tickets_converted', cardinality(v_ticket_ids),
        'reservations_released', v_released,
        'parts_converted', v_cancelled_parts,
        'purchases_archived', v_cancelled_purchases
    );
end;
$$;

revoke all on function private.inventory_convert_open_work_to_legacy(uuid)
from public, anon, authenticated;

create or replace function private.validate_inventory_tracker_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_old_enabled boolean;
    v_new_enabled boolean;
    v_parts_enabled boolean;
begin
    if coalesce(new.tracker_config -> 'customization' ->> 'modules', 'false') <> 'true' then
        new.tracker_config := jsonb_set(
            coalesce(new.tracker_config, '{}'::jsonb),
            '{modules,inventory}',
            'false'::jsonb,
            true
        );
    end if;

    v_old_enabled := public.aida_config_bool(
        coalesce(old.tracker_config, '{}'::jsonb), 'modules', 'inventory', false
    );
    v_new_enabled := public.aida_config_bool(
        coalesce(new.tracker_config, '{}'::jsonb), 'modules', 'inventory', false
    );
    v_parts_enabled := public.aida_config_bool(
        coalesce(new.tracker_config, '{}'::jsonb), 'workflow', 'parts_control', true
    );

    if v_new_enabled and not v_parts_enabled then
        raise exception 'Ative o Controle de compra de pecas antes de ativar o Estoque.';
    end if;

    if v_old_enabled and not v_new_enabled then
        perform private.inventory_convert_open_work_to_legacy(new.id);
    end if;

    return new;
end;
$$;

revoke all on function private.validate_inventory_tracker_config()
from public, anon, authenticated;

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
                'ordered_quantity', coalesce(x.ordered_quantity, 0),
                'missing_quantity', coalesce(x.missing_quantity, 0),
                'consumed_quantity', coalesce(x.consumed_quantity, 0),
                'pending_purchase_count', coalesce(x.pending_purchase_count, 0),
                'open_purchase_count', coalesce(p.open_purchase_count, 0),
                'open_purchase_ids', coalesce(p.open_purchase_ids, '[]'::jsonb),
                'purchase_state', case
                    when coalesce(p.open_purchase_count, 0) > 0 then 'awaiting_receipt'
                    when coalesce(x.pending_purchase_count, 0) > 0 then 'awaiting_purchase'
                    else 'ready'
                end
            )
        ) order by t.id)
        from public.tickets t
        left join lateral (
            select count(*) item_count,
                   coalesce(sum(tp.requested_quantity), 0) requested_quantity,
                   coalesce(sum(coalesce(r.reserved_quantity, 0)), 0) reserved_quantity,
                   coalesce(sum(coalesce(a.ordered_quantity, 0)), 0) ordered_quantity,
                   coalesce(sum(greatest(0, tp.requested_quantity
                       - coalesce(r.reserved_quantity, 0)
                       - coalesce(a.ordered_quantity, 0))), 0) missing_quantity,
                   coalesce(sum(coalesce(r.consumed_quantity, 0)), 0) consumed_quantity,
                   count(*) filter (
                       where tp.status in ('partial', 'purchase_pending')
                         and greatest(0, tp.requested_quantity
                             - coalesce(r.reserved_quantity, 0)
                             - coalesce(a.ordered_quantity, 0)) > 0
                   ) pending_purchase_count
              from public.ticket_part_items tp
              left join lateral (
                  select coalesce(sum(ir.reserved_quantity - ir.consumed_quantity - ir.released_quantity), 0) reserved_quantity,
                         coalesce(sum(ir.consumed_quantity), 0) consumed_quantity
                    from public.inventory_reservations ir
                   where ir.workspace_id = tp.workspace_id
                     and ir.ticket_part_item_id = tp.id
              ) r on true
              left join lateral (
                  select coalesce(sum(pa.allocated_quantity - pa.fulfilled_quantity), 0) ordered_quantity
                    from public.inventory_purchase_allocations pa
                    join public.inventory_purchase_items pi
                      on pi.workspace_id = pa.workspace_id and pi.id = pa.purchase_item_id
                    join public.inventory_purchases ip
                      on ip.workspace_id = pi.workspace_id and ip.id = pi.purchase_id
                   where pa.workspace_id = tp.workspace_id
                     and pa.ticket_part_item_id = tp.id
                     and ip.status in ('draft', 'ordered', 'partial')
              ) a on true
             where tp.workspace_id = t.workspace_id
               and tp.ticket_id = t.id
               and tp.status <> 'cancelled'
        ) x on true
        left join lateral (
            select count(distinct ip.id) open_purchase_count,
                   coalesce(jsonb_agg(distinct ip.id), '[]'::jsonb) open_purchase_ids
              from public.inventory_purchases ip
              join public.inventory_purchase_items pi
                on pi.workspace_id = ip.workspace_id and pi.purchase_id = ip.id
              join public.inventory_purchase_allocations pa
                on pa.workspace_id = pi.workspace_id and pa.purchase_item_id = pi.id
              join public.ticket_part_items tp
                on tp.workspace_id = pa.workspace_id and tp.id = pa.ticket_part_item_id
             where ip.workspace_id = t.workspace_id
               and ip.status in ('draft', 'ordered', 'partial')
               and tp.ticket_id = t.id
        ) p on true
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