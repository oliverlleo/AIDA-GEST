-- Devolucao posterior de peca consumida na OS.
begin;

alter table public.inventory_reservations
    add column if not exists returned_quantity numeric(14,3) not null default 0;

alter table public.inventory_reservations
    drop constraint if exists inventory_reservations_quantities_check;
alter table public.inventory_reservations
    add constraint inventory_reservations_quantities_check check (
        reserved_quantity > 0
        and consumed_quantity >= 0
        and released_quantity >= 0
        and returned_quantity >= 0
        and consumed_quantity + released_quantity <= reserved_quantity
        and returned_quantity <= consumed_quantity
    );

create or replace function public.return_ticket_inventory(
    p_reservation_id uuid,
    p_quantity numeric,
    p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_reservation public.inventory_reservations%rowtype;
    v_part public.ticket_part_items%rowtype;
    v_ticket public.tickets%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');
    if p_quantity is null or p_quantity <= 0
       or length(btrim(coalesce(p_reason, ''))) < 5 then
        raise exception 'Informe quantidade e motivo da devolucao.';
    end if;
    select * into v_reservation
    from public.inventory_reservations r
    where r.workspace_id = v_ctx.workspace_id and r.id = p_reservation_id
    for update;
    if not found or v_reservation.consumed_quantity - v_reservation.returned_quantity < p_quantity then
        raise exception 'Quantidade de devolucao invalida.';
    end if;
    select * into v_part from public.ticket_part_items tp
    where tp.workspace_id = v_ctx.workspace_id and tp.id = v_reservation.ticket_part_item_id;
    select * into v_ticket from public.tickets t
    where t.workspace_id = v_ctx.workspace_id and t.id = v_part.ticket_id;
    if not (
        v_ctx.is_admin
        or (
            v_ctx.is_technician
            and v_ticket.technician_id = v_ctx.actor_employee_id
        )
    ) then raise exception 'Somente o tecnico responsavel ou um administrador pode devolver a peca.'; end if;

    update public.inventory_balances
    set physical_quantity = physical_quantity + p_quantity, updated_at = now()
    where workspace_id = v_ctx.workspace_id
      and item_id = v_reservation.item_id
      and location_id = v_reservation.location_id;
    update public.inventory_reservations
    set returned_quantity = returned_quantity + p_quantity, updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_reservation_id;
    insert into public.inventory_movements(
        workspace_id, item_id, location_id, movement_type,
        physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
        reason, actor_user_id, actor_employee_id, actor_name
    ) values (
        v_ctx.workspace_id, v_reservation.item_id, v_reservation.location_id,
        'return', p_quantity, 0, v_ticket.id, v_part.id,
        btrim(p_reason), v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
    );
    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        v_ticket.id,
        'Devolveu Peca ao Estoque',
        format(
            '**%s** devolveu **%s x %s** da **OS %s** ao estoque. Motivo: **%s**.',
            v_ctx.actor_name, p_quantity, v_part.requested_name_snapshot,
            coalesce(v_ticket.os_number, 'nao informada'), btrim(p_reason)
        ),
        v_ctx.actor_name
    );
    return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.return_ticket_inventory(uuid, numeric, text) from public;
grant execute on function public.return_ticket_inventory(uuid, numeric, text)
to anon, authenticated;

commit;
