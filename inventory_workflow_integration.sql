-- Integracao transacional entre Estoque, Compra de Pecas e o fluxo das OS.
-- Depende de inventory_module_foundation.sql.

begin;

create or replace function private.inventory_sync_ticket_summary(
    p_workspace_id uuid,
    p_ticket_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_summary text;
    v_status text;
begin
    select string_agg(
        trim(trailing '.' from trim(to_char(tp.requested_quantity, 'FM999999990.999')))
        || 'x ' || tp.requested_name_snapshot,
        E'\n' order by tp.created_at, tp.id
    )
    into v_summary
    from public.ticket_part_items tp
    where tp.workspace_id = p_workspace_id
      and tp.ticket_id = p_ticket_id
      and tp.status not in ('cancelled', 'released');

    select case
        when count(*) filter (where tp.status in ('partial', 'purchase_pending')) > 0 then 'Pendente'
        when count(*) filter (where tp.status in ('reserved', 'ready')) > 0 then 'Reservado'
        when count(*) filter (where tp.status = 'consumed') > 0 then 'Utilizado'
        when count(*) > 0 then 'Pendente'
        else 'N/A'
    end
    into v_status
    from public.ticket_part_items tp
    where tp.workspace_id = p_workspace_id
      and tp.ticket_id = p_ticket_id
      and tp.status <> 'cancelled';

    update public.tickets t
    set parts_needed = nullif(v_summary, ''),
        parts_status = coalesce(v_status, 'N/A'),
        updated_at = now()
    where t.workspace_id = p_workspace_id and t.id = p_ticket_id;
end;
$$;

revoke all on function private.inventory_sync_ticket_summary(uuid, uuid)
from public, anon, authenticated;

create or replace function private.inventory_allocate_ticket_parts(
    p_workspace_id uuid,
    p_ticket_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_part record;
    v_balance record;
    v_existing numeric(14,3);
    v_missing numeric(14,3);
    v_take numeric(14,3);
    v_total_requested numeric(14,3) := 0;
    v_total_reserved numeric(14,3) := 0;
    v_shortages jsonb := '[]'::jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    if v_ctx.workspace_id is distinct from p_workspace_id then
        raise exception 'Acesso negado ao estoque de outra empresa.';
    end if;

    for v_part in
        select
            tp.*,
            i.default_location_id,
            i.track_stock
        from public.ticket_part_items tp
        join public.inventory_items i
          on i.workspace_id = tp.workspace_id and i.id = tp.requested_item_id
        where tp.workspace_id = p_workspace_id
          and tp.ticket_id = p_ticket_id
          and tp.status in (
              'needed', 'pending_approval', 'partial', 'purchase_pending'
          )
        order by tp.created_at, tp.id
        for update of tp
    loop
        select coalesce(sum(
            r.reserved_quantity - r.consumed_quantity - r.released_quantity
        ), 0)
        into v_existing
        from public.inventory_reservations r
        where r.workspace_id = p_workspace_id
          and r.ticket_part_item_id = v_part.id
          and r.status = 'active';

        v_total_requested := v_total_requested + v_part.requested_quantity;
        v_missing := greatest(0, v_part.requested_quantity - v_existing);

        if v_part.track_stock and v_missing > 0 then
            for v_balance in
                select b.id, b.location_id, b.available_quantity
                from public.inventory_balances b
                join public.inventory_locations l
                  on l.workspace_id = b.workspace_id and l.id = b.location_id
                where b.workspace_id = p_workspace_id
                  and b.item_id = v_part.requested_item_id
                  and b.available_quantity > 0
                  and l.active
                order by
                    case when b.location_id = v_part.default_location_id then 0 else 1 end,
                    l.normalized_address,
                    b.location_id
                for update of b
            loop
                exit when v_missing <= 0;
                v_take := least(v_missing, v_balance.available_quantity);
                if v_take <= 0 then continue; end if;

                update public.inventory_balances
                set reserved_quantity = reserved_quantity + v_take,
                    updated_at = now()
                where id = v_balance.id and workspace_id = p_workspace_id;

                insert into public.inventory_reservations(
                    workspace_id, ticket_part_item_id, item_id, location_id,
                    reserved_quantity
                ) values (
                    p_workspace_id, v_part.id, v_part.requested_item_id,
                    v_balance.location_id, v_take
                );

                insert into public.inventory_movements(
                    workspace_id, item_id, location_id, movement_type,
                    physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
                    reason, actor_user_id, actor_employee_id, actor_name
                ) values (
                    p_workspace_id, v_part.requested_item_id, v_balance.location_id,
                    'reserve', 0, v_take, p_ticket_id, v_part.id,
                    'Reserva para OS',
                    v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
                );

                v_existing := v_existing + v_take;
                v_missing := v_missing - v_take;
            end loop;
        end if;

        v_total_reserved := v_total_reserved + v_existing;

        if v_existing >= v_part.requested_quantity then
            update public.ticket_part_items
            set status = 'reserved', approved_at = coalesce(approved_at, now()),
                updated_at = now()
            where id = v_part.id and workspace_id = p_workspace_id;
        elsif v_existing > 0 then
            update public.ticket_part_items
            set status = 'partial', approved_at = coalesce(approved_at, now()),
                updated_at = now()
            where id = v_part.id and workspace_id = p_workspace_id;
            v_shortages := v_shortages || jsonb_build_array(jsonb_build_object(
                'ticket_part_item_id', v_part.id,
                'item_id', v_part.requested_item_id,
                'name', v_part.requested_name_snapshot,
                'requested_quantity', v_part.requested_quantity,
                'reserved_quantity', v_existing,
                'missing_quantity', v_part.requested_quantity - v_existing
            ));
        else
            update public.ticket_part_items
            set status = 'purchase_pending',
                approved_at = coalesce(approved_at, now()),
                updated_at = now()
            where id = v_part.id and workspace_id = p_workspace_id;
            v_shortages := v_shortages || jsonb_build_array(jsonb_build_object(
                'ticket_part_item_id', v_part.id,
                'item_id', v_part.requested_item_id,
                'name', v_part.requested_name_snapshot,
                'requested_quantity', v_part.requested_quantity,
                'reserved_quantity', 0,
                'missing_quantity', v_part.requested_quantity
            ));
        end if;
    end loop;

    perform private.inventory_sync_ticket_summary(p_workspace_id, p_ticket_id);

    return jsonb_build_object(
        'requested_quantity', v_total_requested,
        'reserved_quantity', v_total_reserved,
        'missing_quantity', greatest(0, v_total_requested - v_total_reserved),
        'fully_reserved', v_total_requested > 0 and v_total_reserved >= v_total_requested,
        'shortages', v_shortages
    );
end;
$$;

revoke all on function private.inventory_allocate_ticket_parts(uuid, uuid)
from public, anon, authenticated;

create or replace function private.inventory_pause_repair_for_shortage(
    p_workspace_id uuid,
    p_ticket_id uuid,
    p_shortages jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_config jsonb;
    v_timer boolean;
    v_elapsed integer;
    v_shortage_text text;
begin
    select * into v_ctx from public.get_current_actor_context();
    select * into v_ticket
    from public.tickets t
    where t.workspace_id = p_workspace_id and t.id = p_ticket_id
    for update;

    if not found or v_ticket.status <> 'Andamento Reparo'
       or v_ticket.repair_start_at is null then
        raise exception 'Somente um reparo iniciado pode ser pausado por falta de estoque.';
    end if;

    select coalesce(w.tracker_config, '{}'::jsonb)
    into v_config
    from public.workspaces w
    where w.id = p_workspace_id;

    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := case
        when v_timer then coalesce(v_ticket.repair_elapsed_seconds, 0)
            + greatest(0, extract(epoch from (now() - v_ticket.repair_start_at))::integer)
        else 0
    end;

    select string_agg(
        trim(trailing '.' from trim(to_char(
            (item ->> 'missing_quantity')::numeric, 'FM999999990.999'
        ))) || 'x ' || (item ->> 'name'),
        ', '
    )
    into v_shortage_text
    from jsonb_array_elements(coalesce(p_shortages, '[]'::jsonb)) item;

    update public.tickets
    set status = 'Compra Peca',
        parts_status = 'Pendente',
        repair_elapsed_seconds = v_elapsed,
        repair_paused_at = now(),
        repair_start_at = null,
        updated_at = now()
    where workspace_id = p_workspace_id and id = p_ticket_id;

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        'Pausou Reparo por Falta de Estoque',
        format(
            'O reparo da **OS %s**, aparelho **%s** de **%s**, foi pausado por **%s**. Falta comprar: **%s**.%s',
            coalesce(v_ticket.os_number, 'não informada'),
            coalesce(v_ticket.device_model, 'não informado'),
            coalesce(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name,
            coalesce(v_shortage_text, 'peças pendentes'),
            case when v_timer
                then format(' Tempo acumulado: **%s segundos**.', v_elapsed)
                else ''
            end
        ),
        v_ctx.actor_name
    );

    return v_elapsed;
end;
$$;

revoke all on function private.inventory_pause_repair_for_shortage(uuid, uuid, jsonb)
from public, anon, authenticated;

create or replace function public.request_ticket_inventory_parts(
    p_ticket_id uuid,
    p_items jsonb,
    p_stage text,
    p_allocate_now boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_item jsonb;
    v_catalog public.inventory_items%rowtype;
    v_quantity numeric(14,3);
    v_result jsonb;
    v_route text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    if p_stage not in ('analysis', 'direct_repair', 'repair', 'warranty') then
        raise exception 'Etapa de solicitacao invalida.';
    end if;
    if p_items is null or jsonb_typeof(p_items) <> 'array'
       or jsonb_array_length(p_items) < 1
       or jsonb_array_length(p_items) > 50 then
        raise exception 'Informe entre 1 e 50 itens.';
    end if;

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null
    for update;
    if not found then raise exception 'OS nao encontrada.'; end if;

    if p_stage in ('analysis', 'warranty') and v_ticket.status <> 'Analise Tecnica' then
        raise exception 'As pecas da analise so podem ser informadas durante a analise tecnica.';
    end if;
    if p_stage = 'repair' and (
        v_ticket.status <> 'Andamento Reparo' or v_ticket.repair_start_at is null
    ) then
        raise exception 'Inicie o reparo antes de solicitar uma nova peca.';
    end if;
    if p_stage in ('analysis', 'repair', 'warranty')
       and not (
            v_ctx.is_admin
            or (
                v_ctx.is_technician
                and v_ticket.technician_id = v_ctx.actor_employee_id
            )
       ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode solicitar estas pecas.';
    end if;
    if p_stage = 'direct_repair' and not (v_ctx.is_admin or v_ctx.is_attendant) then
        raise exception 'Somente administradores e atendentes podem preparar reparo direto.';
    end if;

    if exists (
        select 1
        from public.ticket_part_items tp
        where tp.workspace_id = v_ctx.workspace_id
          and tp.ticket_id = p_ticket_id
          and tp.request_stage = p_stage
          and tp.status not in ('cancelled', 'released', 'consumed')
    ) then
        raise exception 'Esta OS ja possui uma solicitacao ativa nesta etapa.';
    end if;

    for v_item in select value from jsonb_array_elements(p_items)
    loop
        begin
            v_quantity := (v_item ->> 'quantity')::numeric;
            select * into v_catalog
            from public.inventory_items i
            where i.id = (v_item ->> 'item_id')::uuid
              and i.workspace_id = v_ctx.workspace_id
              and i.active;
        exception when others then
            raise exception 'Item ou quantidade invalida na solicitacao.';
        end;

        if not found then raise exception 'Item do estoque nao encontrado.'; end if;
        if v_quantity is null or v_quantity <= 0 or v_quantity > 999999 then
            raise exception 'Quantidade invalida para %.', v_catalog.name;
        end if;
        if not v_catalog.allow_decimal and v_quantity <> trunc(v_quantity) then
            raise exception '% aceita apenas quantidades inteiras.', v_catalog.name;
        end if;

        if nullif(v_item ->> 'original_item_id', '') is not null and not exists (
            select 1 from public.inventory_item_relations rel
            where rel.workspace_id = v_ctx.workspace_id
              and rel.source_item_id = (v_item ->> 'original_item_id')::uuid
              and rel.target_item_id = v_catalog.id
              and rel.relation_type = v_item ->> 'substitution_type'
        ) then
            raise exception 'A alternativa selecionada nao possui vinculo valido.';
        end if;

        insert into public.ticket_part_items(
            workspace_id, ticket_id, requested_item_id, original_item_id,
            substitution_type, requested_name_snapshot,
            requested_quantity, request_stage, status, notes,
            requested_by_user_id, requested_by_employee_id, requested_by_name
        ) values (
            v_ctx.workspace_id, p_ticket_id, v_catalog.id,
            nullif(v_item ->> 'original_item_id', '')::uuid,
            nullif(v_item ->> 'substitution_type', ''), v_catalog.name,
            v_quantity, p_stage,
            case when p_allocate_now then 'needed' else 'pending_approval' end,
            nullif(btrim(v_item ->> 'notes'), ''),
            v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
        );

        if nullif(v_item ->> 'original_item_id', '') is not null then
            insert into public.ticket_logs(ticket_id, action, details, user_name)
            select p_ticket_id, 'Escolheu Peça Alternativa', format(
                '**%s** escolheu **%s** como %s de **%s** para a **OS %s**.',
                v_ctx.actor_name,
                v_catalog.name,
                case when v_item ->> 'substitution_type' = 'equivalent' then 'equivalente' else 'substituta' end,
                original.name,
                coalesce(v_ticket.os_number, 'não informada')
            ), v_ctx.actor_name
            from public.inventory_items original
            where original.workspace_id = v_ctx.workspace_id
              and original.id = (v_item ->> 'original_item_id')::uuid;
        end if;
    end loop;

    perform private.inventory_sync_ticket_summary(v_ctx.workspace_id, p_ticket_id);

    if not p_allocate_now then
        insert into public.ticket_logs(ticket_id, action, details, user_name)
        values (
            p_ticket_id,
            'Registrou Peças Necessárias',
            format(
                '**%s** registrou as peças necessárias para a **OS %s**. A reserva será feita após a aprovação.',
                v_ctx.actor_name, coalesce(v_ticket.os_number, 'não informada')
            ),
            v_ctx.actor_name
        );
        return jsonb_build_object(
            'success', true,
            'route', 'pending_approval',
            'fully_reserved', false,
            'shortages', '[]'::jsonb
        );
    end if;

    v_result := private.inventory_allocate_ticket_parts(v_ctx.workspace_id, p_ticket_id);

    if coalesce((v_result ->> 'fully_reserved')::boolean, false) then
        v_route := 'repair';
        if p_stage = 'direct_repair' then
            update public.tickets
            set status = 'Andamento Reparo', parts_status = 'Reservado', updated_at = now()
            where workspace_id = v_ctx.workspace_id and id = p_ticket_id;
        end if;
        insert into public.ticket_logs(ticket_id, action, details, user_name)
        values (
            p_ticket_id,
            'Reservou Peças do Estoque',
            format(
                '**%s** reservou todas as peças da **OS %s**. O reparo pode continuar sem pausa.',
                v_ctx.actor_name, coalesce(v_ticket.os_number, 'não informada')
            ),
            v_ctx.actor_name
        );
    else
        v_route := 'purchase';
        if p_stage = 'repair' then
            perform private.inventory_pause_repair_for_shortage(
                v_ctx.workspace_id, p_ticket_id, v_result -> 'shortages'
            );
        else
            update public.tickets
            set status = 'Compra Peca', parts_status = 'Pendente', updated_at = now()
            where workspace_id = v_ctx.workspace_id and id = p_ticket_id;
            insert into public.ticket_logs(ticket_id, action, details, user_name)
            values (
                p_ticket_id,
                'Encaminhou Faltas para Compra',
                format(
                    '**%s** reservou o saldo disponível da **OS %s** e encaminhou somente a quantidade faltante para compra.',
                    v_ctx.actor_name, coalesce(v_ticket.os_number, 'não informada')
                ),
                v_ctx.actor_name
            );
        end if;
    end if;

    return v_result || jsonb_build_object('success', true, 'route', v_route);
end;
$$;

revoke all on function public.request_ticket_inventory_parts(uuid, jsonb, text, boolean)
from public;
grant execute on function public.request_ticket_inventory_parts(uuid, jsonb, text, boolean)
to anon, authenticated;

create or replace function public.approve_ticket_with_inventory(p_ticket_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_config jsonb;
    v_result jsonb;
    v_needs_schedule boolean;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null
    for update;

    if not found or v_ticket.status <> 'Aprovacao'
       or v_ticket.budget_status not in ('Enviado', 'Aprovado') then
        raise exception 'A OS nao esta disponivel para aprovacao.';
    end if;

    if not exists (
        select 1 from public.ticket_part_items tp
        where tp.workspace_id = v_ctx.workspace_id
          and tp.ticket_id = p_ticket_id
          and tp.status not in ('cancelled', 'released', 'consumed')
    ) then
        return jsonb_build_object(
            'success', true,
            'route', 'no_inventory_parts',
            'fully_reserved', true
        );
    end if;

    v_result := private.inventory_allocate_ticket_parts(v_ctx.workspace_id, p_ticket_id);

    if not coalesce((v_result ->> 'fully_reserved')::boolean, false) then
        update public.tickets
        set status = 'Compra Peca', budget_status = 'Aprovado',
            parts_status = 'Pendente', updated_at = now()
        where workspace_id = v_ctx.workspace_id and id = p_ticket_id;

        insert into public.ticket_logs(ticket_id, action, details, user_name)
        values (
            p_ticket_id, 'Aprovou Orçamento',
            format(
                'O orçamento da **OS %s** foi aprovado por **%s**. O saldo disponível foi reservado e somente a falta seguirá para compra.',
                coalesce(v_ticket.os_number, 'não informada'), v_ctx.actor_name
            ),
            v_ctx.actor_name
        );
        return v_result || jsonb_build_object('success', true, 'route', 'purchase');
    end if;

    select coalesce(w.tracker_config, '{}'::jsonb)
    into v_config from public.workspaces w where w.id = v_ctx.workspace_id;

    v_needs_schedule :=
        public.aida_config_bool(v_config, 'modules', 'agenda', true)
        and public.aida_ticket_field_mode(v_config, 'repair_schedule', false) <> 'disabled'
        and not exists (
            select 1 from public.ticket_appointments a
            where a.workspace_id = v_ctx.workspace_id
              and a.ticket_id = p_ticket_id
              and a.appointment_type = 'repair'
              and a.status in ('scheduled', 'in_progress')
              and a.deleted_at is null
        );

    if v_needs_schedule then
        update public.tickets
        set budget_status = 'Aprovado', parts_status = 'Reservado', updated_at = now()
        where workspace_id = v_ctx.workspace_id and id = p_ticket_id;
        return v_result || jsonb_build_object(
            'success', true, 'route', 'schedule_repair', 'needs_schedule', true
        );
    end if;

    update public.tickets
    set status = 'Andamento Reparo', budget_status = 'Aprovado',
        parts_status = 'Reservado', updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_ticket_id;

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id, 'Aprovou Orçamento',
        format(
            'O orçamento da **OS %s** foi aprovado por **%s**. Todas as peças foram reservadas e o reparo foi liberado.',
            coalesce(v_ticket.os_number, 'não informada'), v_ctx.actor_name
        ),
        v_ctx.actor_name
    );

    return v_result || jsonb_build_object('success', true, 'route', 'repair');
end;
$$;

revoke all on function public.approve_ticket_with_inventory(uuid) from public;
grant execute on function public.approve_ticket_with_inventory(uuid)
to anon, authenticated;

create or replace function private.inventory_release_ticket_reservations(
    p_workspace_id uuid,
    p_ticket_id uuid,
    p_reason text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_reservation record;
    v_remaining numeric(14,3);
    v_count integer := 0;
begin
    begin
        select * into v_ctx from public.get_current_actor_context();
    exception when others then
        select null::uuid as actor_user_id,
               null::uuid as actor_employee_id,
               'Sistema'::text as actor_name
        into v_ctx;
    end;

    for v_reservation in
        select r.*
        from public.inventory_reservations r
        where r.workspace_id = p_workspace_id
          and r.status = 'active'
          and exists (
              select 1 from public.ticket_part_items tp
              where tp.workspace_id = r.workspace_id
                and tp.id = r.ticket_part_item_id
                and tp.ticket_id = p_ticket_id
          )
        order by r.item_id, r.location_id, r.id
        for update
    loop
        v_remaining := v_reservation.reserved_quantity
            - v_reservation.consumed_quantity
            - v_reservation.released_quantity;
        if v_remaining <= 0 then continue; end if;

        update public.inventory_balances
        set reserved_quantity = reserved_quantity - v_remaining,
            updated_at = now()
        where workspace_id = p_workspace_id
          and item_id = v_reservation.item_id
          and location_id = v_reservation.location_id;

        update public.inventory_reservations
        set released_quantity = released_quantity + v_remaining,
            status = 'released', updated_at = now()
        where id = v_reservation.id and workspace_id = p_workspace_id;

        insert into public.inventory_movements(
            workspace_id, item_id, location_id, movement_type,
            physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
            reason, actor_user_id, actor_employee_id, actor_name
        ) values (
            p_workspace_id, v_reservation.item_id, v_reservation.location_id,
            'release', 0, -v_remaining, p_ticket_id,
            v_reservation.ticket_part_item_id, p_reason,
            v_ctx.actor_user_id, v_ctx.actor_employee_id,
            coalesce(v_ctx.actor_name, 'Sistema')
        );
        v_count := v_count + 1;
    end loop;

    update public.ticket_part_items
    set status = 'released', updated_at = now()
    where workspace_id = p_workspace_id
      and ticket_id = p_ticket_id
      and status in ('reserved', 'partial', 'ready');

    perform private.inventory_sync_ticket_summary(p_workspace_id, p_ticket_id);
    return v_count;
end;
$$;

revoke all on function private.inventory_release_ticket_reservations(uuid, uuid, text)
from public, anon, authenticated;

create or replace function private.inventory_release_on_ticket_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if (
        new.deleted_at is not null
        or new.status = 'Finalizado'
        or (
            new.status = 'Retirada Cliente'
            and coalesce(new.budget_status, '') = 'Negado'
        )
    ) and (
        old.deleted_at is distinct from new.deleted_at
        or old.status is distinct from new.status
        or old.budget_status is distinct from new.budget_status
    ) then
        perform private.inventory_release_ticket_reservations(
            new.workspace_id,
            new.id,
            case
                when new.deleted_at is not null then 'OS excluida'
                when new.budget_status = 'Negado' then 'Orcamento negado'
                else 'OS finalizada'
            end
        );
    end if;
    return new;
end;
$$;

revoke all on function private.inventory_release_on_ticket_transition()
from public, anon, authenticated;

drop trigger if exists aida_release_inventory_on_ticket_transition on public.tickets;
create trigger aida_release_inventory_on_ticket_transition
after update of status, budget_status, deleted_at on public.tickets
for each row execute function private.inventory_release_on_ticket_transition();

commit;
