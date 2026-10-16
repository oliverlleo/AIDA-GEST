-- Restore original command definitions, signatures and authorization exactly.
BEGIN;
CREATE OR REPLACE FUNCTION public.create_ticket_appointment(p_ticket_id uuid, p_technician_id uuid, p_appointment_type text, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket_id is null or p_technician_id is null then
        raise exception 'Chamado e técnico são obrigatórios.';
    end if;
    if p_appointment_type is null or p_appointment_type not in ('analysis', 'repair') then
        raise exception 'Tipo de agendamento inválido. Use analysis ou repair.';
    end if;
    if p_scheduled_start is null or p_scheduled_end is null or p_scheduled_end <= p_scheduled_start then
        raise exception 'Período do agendamento inválido.';
    end if;

    select t.technician_id, t.status
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Chamado não encontrado ou não pertence ao workspace.';
    end if;
    if not exists (
        select 1 from public.employees e
        where e.id = p_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;

    if not (v_ctx.is_admin or v_ctx.is_attendant) then
        if not v_ctx.is_technician
           or p_technician_id <> v_ctx.actor_employee_id
           or not (
               coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
               or (v_ticket.technician_id is null and
                   v_ticket.status in ('Analise Tecnica', 'Andamento Reparo', 'Teste Final'))
           ) then
            raise exception 'Acesso negado para criar este agendamento.';
        end if;
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            pg_catalog.concat_ws(
                ':', 'aida_ticket_appointment', p_ticket_id::text, p_appointment_type
            ),
            0
        )
    );

    return private.create_ticket_appointment(
        p_ticket_id, p_technician_id, p_appointment_type,
        p_scheduled_start, p_scheduled_end, p_notes
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.request_ticket_inventory_parts(p_ticket_id uuid, p_items jsonb, p_stage text, p_allocate_now boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
                and coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
            )
       ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode solicitar estas pecas.';
    end if;
    if p_stage = 'direct_repair' and not (v_ctx.is_admin or v_ctx.is_attendant) then
        raise exception 'Somente administradores e atendentes podem preparar reparo direto.';
    end if;

    if p_stage is null or p_allocate_now is null then
        raise exception 'Etapa e decisao de reserva sao obrigatorias.' using errcode='22023';
    end if;
    if p_stage in ('analysis','warranty') and p_allocate_now then
        raise exception 'A reserva exige aprovacao do orcamento ou conclusao da garantia.' using errcode='42501';
    end if;
    if p_stage in ('direct_repair','repair') and (v_ticket.budget_status is distinct from 'Aprovado' or v_ticket.status not in ('Andamento Reparo','Compra Peca')) then
        raise exception 'A reserva para reparo exige orcamento aprovado e fase de reparo ou compra.' using errcode='42501';
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
$function$;

CREATE OR REPLACE FUNCTION public.approve_ticket_with_inventory(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.create_ticket_appointment(p_ticket_id uuid, p_technician_id uuid, p_appointment_type text, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ws_id uuid;
    v_app_id uuid;
    v_log_action text;
    v_type_label text;
    v_ticket record;
    v_technician_name text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    IF p_appointment_type NOT IN ('analysis', 'repair') THEN
        RAISE EXCEPTION 'Tipo de agendamento inválido. Use analysis ou repair.';
    END IF;

    SELECT t.os_number, t.device_model, t.client_name
    INTO v_ticket
    FROM public.tickets AS t
    WHERE t.id = p_ticket_id
      AND t.workspace_id = v_ws_id
      AND t.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chamado não encontrado ou não pertence ao workspace.';
    END IF;

    SELECT e.name
    INTO v_technician_name
    FROM public.employees AS e
    WHERE e.id = p_technician_id
      AND e.workspace_id = v_ws_id
      AND e.deleted_at IS NULL;

    IF v_technician_name IS NULL THEN
        RAISE EXCEPTION 'Técnico não encontrado ou não pertence ao workspace.';
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND p_technician_id <> v_ctx.actor_employee_id
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode agendar na própria agenda.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.ticket_appointments AS a
        WHERE a.ticket_id = p_ticket_id
          AND a.workspace_id = v_ws_id
          AND a.deleted_at IS NULL
          AND a.status <> 'cancelled'
          AND a.appointment_type = p_appointment_type
    ) THEN
        RAISE EXCEPTION 'Já existe um agendamento de % ativo para este chamado. Use a função de remarcação.', p_appointment_type;
    END IF;

    PERFORM public.validate_appointment_capacity(
        v_ws_id, p_technician_id, p_scheduled_start, p_scheduled_end
    );

    INSERT INTO public.ticket_appointments (
        workspace_id, ticket_id, technician_id, appointment_type,
        scheduled_start, scheduled_end, notes,
        created_by_user_id, created_by_employee_id, status
    ) VALUES (
        v_ws_id, p_ticket_id, p_technician_id, p_appointment_type,
        p_scheduled_start, p_scheduled_end, p_notes,
        v_ctx.actor_user_id, v_ctx.actor_employee_id, 'scheduled'
    ) RETURNING id INTO v_app_id;

    IF p_appointment_type = 'repair' THEN
        UPDATE public.tickets
        SET technician_id = p_technician_id,
            updated_at = timezone('utc', now())
        WHERE id = p_ticket_id
          AND workspace_id = v_ws_id;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM public.ticket_appointments AS a
        WHERE a.ticket_id = p_ticket_id
          AND a.appointment_type = 'repair'
          AND a.status <> 'cancelled'
          AND a.deleted_at IS NULL
    ) THEN
        UPDATE public.tickets
        SET technician_id = p_technician_id,
            updated_at = timezone('utc', now())
        WHERE id = p_ticket_id
          AND workspace_id = v_ws_id;
    END IF;

    v_type_label := CASE WHEN p_appointment_type = 'analysis' THEN 'análise' ELSE 'reparo' END;
    v_log_action := CASE WHEN p_appointment_type = 'analysis' THEN 'Agendou Análise' ELSE 'Agendou Reparo' END;

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        p_ticket_id,
        v_log_action,
        format(
            'Agendamento de %s da OS **%s** — aparelho **%s** do cliente **%s** — criado com o técnico **%s** para **%s**, das **%s** às **%s**.',
            v_type_label,
            COALESCE(v_ticket.os_number::text, 'não informada'),
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_technician_name,
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            to_char(p_scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')
        ),
        v_ctx.actor_name
    );

    RETURN jsonb_build_object('success', true, 'appointment_id', v_app_id);
END;
$function$;

DROP FUNCTION private.ticket_command_receipt(uuid,uuid);
DROP FUNCTION private.assert_ticket_command_snapshot(uuid,uuid);
NOTIFY pgrst,'reload schema';
COMMIT;
