-- Restore only this audit's function definitions, policies and notification privileges.
-- Does not undo Supabase Auth or earlier current-role guards.
BEGIN;
CREATE OR REPLACE FUNCTION public.aida_enforce_ticket_actor_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
BEGIN
    -- Operacoes internas e service_role continuam disponiveis para manutencao.
    IF COALESCE(auth.role(), '') NOT IN ('anon', 'authenticated') THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    IF TG_OP = 'INSERT' THEN
        NEW.workspace_id := v_ctx.workspace_id;
        NEW.created_by := COALESCE(v_ctx.actor_employee_id, v_ctx.actor_user_id);
        NEW.created_by_name := v_ctx.actor_name;
        RETURN NEW;
    END IF;

    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.public_token IS DISTINCT FROM OLD.public_token
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_by_name IS DISTINCT FROM OLD.created_by_name THEN
        RAISE EXCEPTION 'Acesso negado: campos de identidade da OS nao podem ser alterados.';
    END IF;

    IF NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND NEW.technician_id IS DISTINCT FROM OLD.technician_id THEN
        RAISE EXCEPTION 'Acesso negado: este cargo nao pode trocar o tecnico da OS.';
    END IF;

    -- O testador atua apenas no resultado do teste. Dados cadastrais, fotos,
    -- pecas, tecnico e demais campos da OS permanecem fora de sua permissao.
    IF NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND NOT v_ctx.is_technician
       AND 'tester' = ANY(COALESCE(v_ctx.actor_roles, '{}'::text[]))
       AND (
           to_jsonb(NEW) - ARRAY[
               'status', 'previous_status', 'test_start_at', 'test_notes',
               'deadline', 'priority', 'repair_start_at', 'updated_at',
               'outsourced_deadline', 'outsourced_return_count', 'outsourced_notes',
               'overview_queue_stage', 'overview_queue_entered_at'
           ]::text[]
       ) IS DISTINCT FROM (
           to_jsonb(OLD) - ARRAY[
               'status', 'previous_status', 'test_start_at', 'test_notes',
               'deadline', 'priority', 'repair_start_at', 'updated_at',
               'outsourced_deadline', 'outsourced_return_count', 'outsourced_notes',
               'overview_queue_stage', 'overview_queue_entered_at'
           ]::text[]
       ) THEN
        RAISE EXCEPTION 'Acesso negado: testador so pode registrar o andamento e o resultado do teste.';
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_ticket_analysis(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id
       AND t.workspace_id = v_ctx.workspace_id
       AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Analise Tecnica' OR v_ticket.analysis_started_at IS NOT NULL THEN
        RAISE EXCEPTION 'A OS não está disponível para iniciar análise.';
    END IF;

    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode iniciar a própria análise.';
    END IF;

    IF public.aida_config_bool(v_config, 'modules', 'agenda', true)
       AND public.aida_ticket_field_mode(v_config, 'analysis_schedule', false) = 'required'
       AND NOT EXISTS (
           SELECT 1 FROM public.ticket_appointments a
            WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
              AND a.appointment_type = 'analysis' AND a.status IN ('scheduled', 'in_progress')
              AND a.deleted_at IS NULL
       ) THEN
        RAISE EXCEPTION 'Agende a análise antes de iniciar o serviço.';
    END IF;

    UPDATE public.tickets
       SET analysis_started_at = now(), updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id
     RETURNING * INTO v_ticket;

    UPDATE public.ticket_appointments
       SET status = 'in_progress', actual_start = COALESCE(actual_start, now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'analysis' AND a.status = 'scheduled' AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Iniciou Análise', format(
        'A análise da OS **%s** — aparelho **%s** do cliente **%s** — foi iniciada por **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name), v_ctx.actor_name);

    RETURN to_jsonb(v_ticket);
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_repair_timer(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'A OS não está disponível para iniciar reparo.';
    END IF;
    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND (NOT v_ctx.is_technician OR v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id) THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode iniciar o próprio reparo.';
    END IF;
    IF v_ticket.repair_start_at IS NOT NULL THEN
        RAISE EXCEPTION 'O reparo já está em andamento.';
    END IF;

    IF public.aida_config_bool(v_config, 'modules', 'agenda', true)
       AND public.aida_ticket_field_mode(v_config, 'repair_schedule', false) = 'required'
       AND NOT EXISTS (
           SELECT 1 FROM public.ticket_appointments a
            WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
              AND a.appointment_type = 'repair' AND a.status IN ('scheduled', 'in_progress')
              AND a.deleted_at IS NULL
       ) THEN
        RAISE EXCEPTION 'Agende o reparo antes de iniciar o serviço.';
    END IF;

    UPDATE public.tickets SET repair_start_at = now(), repair_paused_at = NULL, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
       SET status = 'in_progress', actual_start = COALESCE(actual_start, now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'repair' AND a.status = 'scheduled' AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Iniciou Execução', format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — iniciado por **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name), v_ctx.actor_name);
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_repair_with_timer(p_ticket_id uuid, p_success boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
    v_timer boolean;
    v_elapsed integer;
    v_next_status text;
    v_details text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'A OS não está disponível para finalizar reparo.';
    END IF;
    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode finalizar o próprio reparo.';
    END IF;

    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := CASE WHEN v_timer THEN COALESCE(v_ticket.repair_elapsed_seconds, 0)
        + CASE WHEN v_ticket.repair_start_at IS NULL THEN 0
               ELSE GREATEST(0, EXTRACT(EPOCH FROM (now() - v_ticket.repair_start_at))::integer) END
        ELSE 0 END;
    v_next_status := CASE WHEN p_success AND public.aida_config_bool(v_config, 'workflow', 'final_test', true)
                          THEN 'Teste Final' ELSE 'Retirada Cliente' END;

    UPDATE public.tickets
       SET status = v_next_status, repair_successful = p_success,
           repair_elapsed_seconds = v_elapsed, repair_end_at = now(), repair_start_at = NULL,
           repair_paused_at = NULL, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
       SET status = 'completed', actual_start = COALESCE(actual_start, now()), actual_end = now(),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'repair' AND a.status IN ('scheduled', 'in_progress') AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    v_details := format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi finalizado por **%s** com resultado **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name,
        CASE WHEN p_success THEN 'sucesso' ELSE 'sem reparo' END);
    IF v_timer THEN v_details := v_details || format(' Tempo total: **%s segundos**.', v_elapsed); END IF;
    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Finalizou Reparo', v_details, v_ctx.actor_name);
    RETURN jsonb_build_object('success', true, 'elapsed_seconds', v_elapsed, 'status', v_next_status);
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_repair_for_parts(p_ticket_id uuid, p_parts_needed text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
    v_parts text := NULLIF(btrim(p_parts_needed), '');
    v_timer boolean;
    v_elapsed integer;
    v_details text;
BEGIN
    IF v_parts IS NULL THEN RAISE EXCEPTION 'Informe a peça ou componente necessário.'; END IF;
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'Somente reparos em andamento podem ser pausados para compra.';
    END IF;
    IF NOT public.aida_config_bool(v_config, 'workflow', 'parts_control', true) THEN
        RAISE EXCEPTION 'O controle de compra de peças está desativado.';
    END IF;
    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode pausar o próprio reparo.';
    END IF;
    IF v_ticket.repair_start_at IS NULL THEN RAISE EXCEPTION 'Inicie o reparo antes de pausá-lo para compra.'; END IF;

    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := CASE WHEN v_timer THEN COALESCE(v_ticket.repair_elapsed_seconds, 0)
        + GREATEST(0, EXTRACT(EPOCH FROM (now() - v_ticket.repair_start_at))::integer) ELSE 0 END;

    UPDATE public.tickets
       SET status = 'Compra Peca',
           parts_needed = CASE WHEN NULLIF(btrim(COALESCE(parts_needed, '')), '') IS NULL THEN v_parts
                               ELSE btrim(parts_needed) || E'\n' || v_parts END,
           parts_status = 'Pendente', repair_elapsed_seconds = v_elapsed,
           repair_paused_at = now(), repair_start_at = NULL, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    v_details := format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi pausado por **%s** para comprar **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name, v_parts);
    IF v_timer THEN v_details := v_details || format(' Tempo contabilizado: **%s segundos**.', v_elapsed); END IF;
    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Pausou Reparo para Compra', v_details, v_ctx.actor_name);
    RETURN jsonb_build_object('success', true, 'elapsed_seconds', v_elapsed);
END;
$function$;

CREATE OR REPLACE FUNCTION public.resume_repair_after_parts(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
    v_timer boolean;
    v_details text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Compra Peca' OR v_ticket.repair_paused_at IS NULL THEN
        RAISE EXCEPTION 'Esta OS não está com um reparo pausado aguardando compra.';
    END IF;
    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode retomar o próprio reparo.';
    END IF;

    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    UPDATE public.tickets
       SET status = 'Andamento Reparo', parts_status = 'Recebido', parts_received_at = now(),
           repair_paused_at = NULL, repair_start_at = now(),
           repair_elapsed_seconds = CASE WHEN v_timer THEN COALESCE(repair_elapsed_seconds, 0) ELSE 0 END,
           repair_resume_count = COALESCE(repair_resume_count, 0) + 1, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
       SET status = 'in_progress', actual_start = COALESCE(actual_start, now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'repair' AND a.status = 'scheduled' AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    v_details := format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi retomado por **%s** após a compra das peças. Novo ciclo iniciado.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name);
    IF v_timer THEN
        v_details := v_details || format(' Tempo já contabilizado: **%s segundos**.', COALESCE(v_ticket.repair_elapsed_seconds, 0));
    END IF;
    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Retomou Reparo após Compra', v_details, v_ctx.actor_name);
    RETURN jsonb_build_object('success', true,
        'elapsed_seconds', CASE WHEN v_timer THEN COALESCE(v_ticket.repair_elapsed_seconds, 0) ELSE 0 END);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_technician_schedule(p_technician_id uuid, p_view text, p_reference_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ws_id uuid;
    v_end_date date;
    v_tz text := 'America/Sao_Paulo';
    v_start_ts timestamptz;
    v_end_ts timestamptz;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    IF NOT EXISTS (SELECT 1 FROM public.employees WHERE id = p_technician_id AND workspace_id = v_ws_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Técnico não encontrado ou não pertence ao workspace.';
    END IF;

    -- Validar permissão
    IF v_ctx.actor_kind = 'employee' AND p_technician_id <> v_ctx.actor_employee_id AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode ver a própria agenda.';
    END IF;

    IF p_view = 'day' THEN
        v_end_date := p_reference_date;
    ELSIF p_view = 'week' THEN
        v_end_date := p_reference_date + 6;
    ELSE
        RAISE EXCEPTION 'View inválida. Use day ou week.';
    END IF;

    v_start_ts := (p_reference_date::timestamp AT TIME ZONE v_tz);
    v_end_ts := ((v_end_date + 1)::timestamp AT TIME ZONE v_tz);

    RETURN (
        WITH apps AS (
            SELECT a.id, a.ticket_id, a.appointment_type, a.scheduled_start, a.scheduled_end, a.status, a.notes, 
                   t.os_number, t.client_name, t.device_model, t.defect_reported, t.analysis_deadline, t.deadline
            FROM public.ticket_appointments a
            JOIN public.tickets t ON t.id = a.ticket_id
            WHERE a.technician_id = p_technician_id
              AND a.workspace_id = v_ws_id
              AND a.deleted_at IS NULL
              AND a.scheduled_start >= v_start_ts
              AND a.scheduled_end <= v_end_ts
        ),
        blocks AS (
            SELECT block_id AS id, block_type, start_at, end_at, reason
            FROM public.get_expanded_blocks(v_ws_id, p_technician_id, p_reference_date, v_end_date)
        )
        SELECT jsonb_build_object(
            'technician_id', p_technician_id,
            'start_date', p_reference_date,
            'end_date', v_end_date,
            'view', p_view,
            'appointments', COALESCE((SELECT jsonb_agg(row_to_json(apps)) FROM apps), '[]'::jsonb),
            'blocks', COALESCE((SELECT jsonb_agg(row_to_json(blocks)) FROM blocks), '[]'::jsonb),
            'counts', jsonb_build_object(
                'total_appointments', (SELECT COUNT(*) FROM apps WHERE status != 'cancelled'),
                'total_blocks', (SELECT COUNT(*) FROM blocks)
            )
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_client_ticket_details_public(p_ticket_id uuid, p_public_token uuid)
 RETURNS TABLE(id uuid, os_number text, device_model text, status text, deadline timestamp with time zone, priority_requested boolean, pickup_available boolean, created_at timestamp with time zone, whatsapp_number text, tracker_config jsonb, delivery_method text, carrier_name text, tracking_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    t.id,
    t.os_number,
    t.device_model,
    t.status,
    t.deadline,
    t.priority_requested,
    t.pickup_available,
    t.created_at,
    w.whatsapp_number,
    w.tracker_config,
    t.delivery_method,
    t.carrier_name,
    t.tracking_code
  FROM public.tickets t
  JOIN public.workspaces w ON w.id = t.workspace_id
  WHERE
    t.id = p_ticket_id
    AND t.public_token = p_public_token
    AND t.deleted_at IS NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_warranty_analysis(p_ticket_id uuid, p_covered boolean, p_report text, p_needs_parts boolean DEFAULT false, p_parts text DEFAULT NULL::text, p_tech_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_parts_enabled boolean;
    v_target_status text;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket_id is null or p_covered is null then
        raise exception 'Informe a OS e a decisao da garantia.';
    end if;
    if length(btrim(coalesce(p_report, ''))) < 20 then
        raise exception 'Preencha um laudo tecnico com pelo menos 20 caracteres.';
    end if;

    select *
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null
     for update;

    if not found or not v_ticket.warranty_claim or v_ticket.warranty_status <> 'pending' then
        raise exception 'Este retorno nao esta aguardando a decisao da garantia.';
    end if;
    if v_ticket.status <> 'Analise Tecnica' then
        raise exception 'A decisao da garantia so pode ser registrada durante a analise tecnica.';
    end if;
    if not (
        coalesce(v_ctx.is_admin, false)
        or (
            coalesce(v_ctx.is_technician, false)
            and v_ticket.technician_id = v_ctx.actor_employee_id
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a analise.';
    end if;

    v_parts_enabled := coalesce(public.aida_warranty_parts_control_enabled(), true);

    if coalesce(p_needs_parts, false) and not coalesce(v_parts_enabled, true) then
        raise exception 'O controle de compra de pecas esta desativado.';
    end if;
    if coalesce(p_needs_parts, false) and length(btrim(coalesce(p_parts, ''))) < 2 then
        raise exception 'Informe as pecas necessarias.';
    end if;

    v_target_status := case
        when not p_covered then 'Aprovacao'
        when coalesce(p_needs_parts, false) then 'Compra Peca'
        else 'Andamento Reparo'
    end;

    update public.tickets t
       set warranty_status = case when p_covered then 'covered' else 'not_covered' end,
           warranty_technical_report = btrim(p_report),
           warranty_needs_parts = coalesce(p_needs_parts, false),
           parts_needed = case when coalesce(p_needs_parts, false) then btrim(p_parts) else null end,
           parts_status = case when coalesce(p_needs_parts, false) then 'Pendente' else 'N/A' end,
           budget_status = case when p_covered then 'Aprovado' else 'Pendente' end,
           tech_notes = coalesce(p_tech_notes, t.tech_notes),
           previous_status = t.status,
           status = v_target_status,
           updated_at = now()
     where t.id = v_ticket.id
     returning * into v_ticket;

    return to_jsonb(v_ticket);
end;
$function$;

CREATE OR REPLACE FUNCTION public.link_warranty_paid_ticket(p_claim_ticket_id uuid, p_paid_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_claim public.tickets%rowtype;
    v_paid public.tickets%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Somente administradores e atendentes podem concluir a conversao.';
    end if;

    select *
      into v_claim
      from public.tickets t
     where t.id = p_claim_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null
     for update;

    if not found then
        raise exception 'Retorno em garantia nao encontrado.';
    end if;

    select *
      into v_paid
      from public.tickets t
     where t.id = p_paid_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Nova OS paga nao encontrada.';
    end if;
    if not v_claim.warranty_claim or v_claim.warranty_status <> 'not_covered' then
        raise exception 'O retorno nao esta disponivel para conversao.';
    end if;
    if v_claim.warranty_converted_ticket_id is not null then
        raise exception 'Este retorno ja foi convertido.';
    end if;
    if v_paid.warranty_source_claim_id is distinct from v_claim.id
       or v_paid.customer_id is distinct from v_claim.customer_id then
        raise exception 'A nova OS nao possui o vinculo esperado com o retorno.';
    end if;

    update public.tickets t
       set warranty_converted_ticket_id = v_paid.id,
           previous_status = t.status,
           status = 'Finalizado',
           budget_status = 'Aprovado',
           repair_successful = false,
           delivered_at = now(),
           updated_at = now()
     where t.id = v_claim.id
     returning * into v_claim;

    return to_jsonb(v_claim);
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_repair_with_inventory(p_ticket_id uuid, p_success boolean, p_usage jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_config jsonb;
    v_timer boolean;
    v_elapsed integer;
    v_next_status text;
    v_reservation record;
    v_usage jsonb;
    v_remaining numeric(14,3);
    v_used numeric(14,3);
    v_unused numeric(14,3);
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    if p_usage is null or jsonb_typeof(p_usage) <> 'array'
       or jsonb_array_length(p_usage) > 100 then
        raise exception 'Confirme o uso das pecas reservadas.';
    end if;

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null
    for update;

    if not found or v_ticket.status <> 'Andamento Reparo'
       or v_ticket.repair_start_at is null then
        raise exception 'A OS nao esta disponivel para finalizar reparo.';
    end if;
    if not (
        v_ctx.is_admin
        or (
            v_ctx.is_technician
            and v_ticket.technician_id = v_ctx.actor_employee_id
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode finalizar o reparo.';
    end if;

    for v_reservation in
        select r.*, tp.ticket_id
        from public.inventory_reservations r
        join public.ticket_part_items tp
          on tp.workspace_id = r.workspace_id and tp.id = r.ticket_part_item_id
        where r.workspace_id = v_ctx.workspace_id
          and tp.ticket_id = p_ticket_id
          and r.status = 'active'
        order by r.item_id, r.location_id, r.id
        for update of r
    loop
        v_remaining := v_reservation.reserved_quantity
            - v_reservation.consumed_quantity
            - v_reservation.released_quantity;
        if v_remaining <= 0 then continue; end if;

        select value into v_usage
        from jsonb_array_elements(p_usage)
        where value ->> 'reservation_id' = v_reservation.id::text
        limit 1;
        if v_usage is null then
            raise exception 'Confirme a quantidade usada de todas as pecas reservadas.';
        end if;
        begin
            v_used := (v_usage ->> 'used_quantity')::numeric;
        exception when others then
            raise exception 'Quantidade utilizada invalida.';
        end;
        if v_used is null or v_used < 0 or v_used > v_remaining then
            raise exception 'A quantidade usada nao pode exceder a reserva.';
        end if;
        v_unused := v_remaining - v_used;

        update public.inventory_balances
        set physical_quantity = physical_quantity - v_used,
            reserved_quantity = reserved_quantity - v_remaining,
            updated_at = now()
        where workspace_id = v_ctx.workspace_id
          and item_id = v_reservation.item_id
          and location_id = v_reservation.location_id;

        if v_used > 0 then
            insert into public.inventory_movements(
                workspace_id, item_id, location_id, movement_type,
                physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
                reason, actor_user_id, actor_employee_id, actor_name
            ) values (
                v_ctx.workspace_id, v_reservation.item_id,
                v_reservation.location_id, 'consume',
                -v_used, -v_used, p_ticket_id, v_reservation.ticket_part_item_id,
                'Peca utilizada no reparo',
                v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
            );
        end if;
        if v_unused > 0 then
            insert into public.inventory_movements(
                workspace_id, item_id, location_id, movement_type,
                physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
                reason, actor_user_id, actor_employee_id, actor_name
            ) values (
                v_ctx.workspace_id, v_reservation.item_id,
                v_reservation.location_id, 'release',
                0, -v_unused, p_ticket_id, v_reservation.ticket_part_item_id,
                'Peca reservada nao utilizada',
                v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
            );
        end if;

        update public.inventory_reservations
        set consumed_quantity = consumed_quantity + v_used,
            released_quantity = released_quantity + v_unused,
            status = case when v_used > 0 then 'consumed' else 'released' end,
            updated_at = now()
        where id = v_reservation.id and workspace_id = v_ctx.workspace_id;
    end loop;

    update public.ticket_part_items tp
    set status = case
            when exists (
                select 1 from public.inventory_reservations r
                where r.workspace_id = tp.workspace_id
                  and r.ticket_part_item_id = tp.id
                  and r.consumed_quantity > 0
            ) then 'consumed'
            else 'released'
        end,
        updated_at = now()
    where tp.workspace_id = v_ctx.workspace_id
      and tp.ticket_id = p_ticket_id
      and tp.status in ('reserved', 'ready');

    perform private.inventory_sync_ticket_summary(v_ctx.workspace_id, p_ticket_id);

    select coalesce(w.tracker_config, '{}'::jsonb)
    into v_config from public.workspaces w where w.id = v_ctx.workspace_id;
    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := case
        when v_timer then coalesce(v_ticket.repair_elapsed_seconds, 0)
            + greatest(0, extract(epoch from (now() - v_ticket.repair_start_at))::integer)
        else 0
    end;
    v_next_status := case
        when p_success and public.aida_config_bool(v_config, 'workflow', 'final_test', true)
            then 'Teste Final'
        else 'Retirada Cliente'
    end;

    update public.tickets
    set status = v_next_status,
        repair_successful = p_success,
        repair_elapsed_seconds = v_elapsed,
        repair_end_at = now(),
        repair_start_at = null,
        repair_paused_at = null,
        updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_ticket_id;

    update public.ticket_appointments
    set status = 'completed',
        actual_start = coalesce(actual_start, now()),
        actual_end = now(),
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = now()
    where id = (
        select a.id from public.ticket_appointments a
        where a.workspace_id = v_ctx.workspace_id
          and a.ticket_id = p_ticket_id
          and a.appointment_type = 'repair'
          and a.status in ('scheduled', 'in_progress')
          and a.deleted_at is null
        order by a.created_at desc limit 1
    );

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        'Finalizou Reparo',
        format(
            'O reparo da **OS %s**, aparelho **%s** de **%s**, foi finalizado por **%s** com resultado **%s**. As peças utilizadas foram baixadas e as não utilizadas voltaram ao disponível.%s',
            coalesce(v_ticket.os_number, 'não informada'),
            coalesce(v_ticket.device_model, 'não informado'),
            coalesce(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name,
            case when p_success then 'sucesso' else 'sem reparo' end,
            case when v_timer
                then format(' Tempo total: **%s segundos**.', v_elapsed)
                else ''
            end
        ),
        v_ctx.actor_name
    );

    return jsonb_build_object(
        'success', true,
        'status', v_next_status,
        'elapsed_seconds', v_elapsed
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_warranty_analysis_with_inventory(p_ticket_id uuid, p_report text, p_tech_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.return_ticket_inventory(p_reservation_id uuid, p_quantity numeric, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_ticket_appointments(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket record;
    v_is_tester boolean;
begin
    select * into v_ctx from public.get_current_actor_context();
    v_is_tester := 'tester' = any(coalesce(v_ctx.actor_roles, '{}'::text[]));

    select t.technician_id, t.status
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Chamado não encontrado ou não pertence ao workspace.';
    end if;
    if not (
        v_ctx.is_admin
        or v_ctx.is_attendant
        or (
            v_ctx.is_technician and (
                v_ticket.technician_id = v_ctx.actor_employee_id
                or (v_ticket.technician_id is null and
                    v_ticket.status in ('Analise Tecnica', 'Andamento Reparo', 'Teste Final'))
            )
        )
        or (v_is_tester and v_ticket.status = 'Teste Final')
    ) then
        raise exception 'Acesso negado aos agendamentos deste chamado.';
    end if;

    return private.get_ticket_appointments(p_ticket_id);
end;
$function$;

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
               v_ticket.technician_id = v_ctx.actor_employee_id
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

CREATE OR REPLACE FUNCTION private.enforce_ticket_warranty()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_origin public.tickets%rowtype;
    v_claim public.tickets%rowtype;
    v_days integer;
    v_start timestamptz;
    v_expiry timestamptz;
begin
    select * into v_ctx from public.get_current_actor_context();

    if new.workspace_id is distinct from v_ctx.workspace_id then
        raise exception 'A OS de garantia deve pertencer a empresa atual.';
    end if;

    v_days := coalesce(public.aida_warranty_days(), 90);

    if tg_op = 'INSERT' then
        if new.warranty_claim then
            if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
                raise exception 'Somente administradores e atendentes podem abrir um retorno em garantia.';
            end if;
            if not coalesce(public.aida_warranty_enabled(), true) then
                raise exception 'A abertura de retornos em garantia esta desativada.';
            end if;
            if new.warranty_origin_ticket_id is null then
                raise exception 'Selecione a OS original da garantia.';
            end if;

            select *
              into v_origin
              from public.tickets t
             where t.id = new.warranty_origin_ticket_id
               and t.workspace_id = new.workspace_id
               and t.deleted_at is null
             for share;

            if not found then
                raise exception 'OS original nao encontrada ou fora da empresa.';
            end if;
            if v_origin.warranty_claim then
                raise exception 'A garantia deve ser vinculada a uma OS de servico original.';
            end if;
            if v_origin.customer_id is null or new.customer_id is distinct from v_origin.customer_id then
                raise exception 'O retorno deve usar o mesmo cliente da OS original.';
            end if;
            if v_origin.repair_successful is distinct from true
               or v_origin.delivered_at is null
               or v_origin.status <> 'Finalizado' then
                raise exception 'A OS original precisa estar finalizada, entregue e com reparo concluido com sucesso.';
            end if;

            v_start := coalesce(v_origin.warranty_start_at, v_origin.delivered_at);
            v_expiry := coalesce(
                v_origin.warranty_expires_at,
                v_start + make_interval(days => coalesce(v_origin.warranty_days, v_days))
            );
            if v_expiry < now() then
                raise exception 'A garantia desta OS expirou em %.', to_char(v_expiry at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
            end if;
            if exists (
                select 1
                  from public.tickets active_claim
                 where active_claim.workspace_id = new.workspace_id
                   and active_claim.warranty_claim
                   and active_claim.warranty_origin_ticket_id = v_origin.id
                   and active_claim.deleted_at is null
                   and active_claim.status <> 'Finalizado'
            ) then
                raise exception 'Ja existe um retorno em garantia aberto para esta OS.';
            end if;

            new.customer_id := v_origin.customer_id;
            new.client_name := v_origin.client_name;
            new.contact_info := coalesce(new.contact_info, v_origin.contact_info);
            new.device_model := v_origin.device_model;
            new.serial_number := v_origin.serial_number;
            new.warranty_source_claim_id := null;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := 'pending';
            new.warranty_days := coalesce(v_origin.warranty_days, v_days);
            new.warranty_start_at := v_start;
            new.warranty_expires_at := v_expiry;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        elsif new.warranty_source_claim_id is not null then
            if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
                raise exception 'Somente administradores e atendentes podem converter um retorno em uma nova OS.';
            end if;

            select *
              into v_claim
              from public.tickets t
             where t.id = new.warranty_source_claim_id
               and t.workspace_id = new.workspace_id
               and t.deleted_at is null
             for share;

            if not found or not v_claim.warranty_claim or v_claim.warranty_status <> 'not_covered' then
                raise exception 'O retorno informado nao esta aguardando uma nova OS paga.';
            end if;
            if v_claim.customer_id is null or new.customer_id is distinct from v_claim.customer_id then
                raise exception 'A nova OS deve usar o mesmo cliente do retorno.';
            end if;
            if v_claim.warranty_converted_ticket_id is not null then
                raise exception 'Este retorno ja foi convertido em uma nova OS.';
            end if;

            new.warranty_claim := false;
            new.warranty_origin_ticket_id := v_claim.warranty_origin_ticket_id;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := null;
            new.warranty_days := null;
            new.warranty_start_at := null;
            new.warranty_expires_at := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        else
            new.warranty_claim := false;
            new.warranty_origin_ticket_id := null;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := null;
            new.warranty_days := null;
            new.warranty_start_at := null;
            new.warranty_expires_at := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        end if;
    else
        if old.warranty_claim is distinct from new.warranty_claim
           or old.warranty_origin_ticket_id is distinct from new.warranty_origin_ticket_id
           or old.warranty_source_claim_id is distinct from new.warranty_source_claim_id then
            raise exception 'Os vinculos da garantia nao podem ser alterados depois da abertura.';
        end if;

        if old.warranty_converted_ticket_id is distinct from new.warranty_converted_ticket_id
           and not (
                old.warranty_claim
                and old.warranty_status = 'not_covered'
                and old.warranty_converted_ticket_id is null
                and new.warranty_converted_ticket_id is not null
                and (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false))
           ) then
            raise exception 'O vinculo da nova OS paga e protegido.';
        end if;

        if old.warranty_claim then
            if new.warranty_status is distinct from old.warranty_status then
                if old.warranty_status <> 'pending'
                   or new.warranty_status not in ('covered', 'not_covered')
                   or old.status <> 'Analise Tecnica' then
                    raise exception 'Decisao de garantia invalida para a etapa atual.';
                end if;
                if not (
                    coalesce(v_ctx.is_admin, false)
                    or (
                        coalesce(v_ctx.is_technician, false)
                        and old.technician_id = v_ctx.actor_employee_id
                    )
                ) then
                    raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a analise da garantia.';
                end if;
                if length(btrim(coalesce(new.warranty_technical_report, ''))) < 20 then
                    raise exception 'Preencha um laudo tecnico com pelo menos 20 caracteres.';
                end if;
                if coalesce(new.warranty_needs_parts, false)
                   and length(btrim(coalesce(new.parts_needed, ''))) < 2 then
                    raise exception 'Informe as pecas necessarias.';
                end if;
                if coalesce(new.warranty_needs_parts, false)
                   and not coalesce(public.aida_warranty_parts_control_enabled(), true) then
                    raise exception 'O controle de compra de pecas esta desativado.';
                end if;

                new.warranty_decided_at := now();
                new.warranty_decided_by := coalesce(v_ctx.actor_employee_id, v_ctx.actor_user_id);
                new.warranty_decided_by_name := v_ctx.actor_name;
            elsif new.warranty_status = 'pending' then
                new.warranty_technical_report := null;
                new.warranty_needs_parts := null;
                new.warranty_decided_at := null;
                new.warranty_decided_by := null;
                new.warranty_decided_by_name := null;
            end if;
        else
            new.warranty_status := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        end if;
    end if;

    -- A successful paid service starts its own warranty when it is delivered.
    -- Warranty claims never reset or extend the original coverage.
    if not new.warranty_claim
       and new.repair_successful is true
       and new.delivered_at is not null then
        new.warranty_days := case
            when tg_op = 'UPDATE' then coalesce(old.warranty_days, v_days)
            else v_days
        end;
        new.warranty_start_at := new.delivered_at;
        new.warranty_expires_at := new.delivered_at + make_interval(days => new.warranty_days);
    end if;

    return new;
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
$function$;

DROP POLICY IF EXISTS "auth_notifications_delete" ON "public"."notifications";
CREATE POLICY "auth_notifications_delete" ON "public"."notifications" AS PERMISSIVE FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE ((t.id = notifications.ticket_id) AND private.has_workspace_permission(t.workspace_id, 'admin'::text)))));
DROP POLICY IF EXISTS "auth_notifications_insert" ON "public"."notifications";
CREATE POLICY "auth_notifications_insert" ON "public"."notifications" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE (t.id = notifications.ticket_id))));
DROP POLICY IF EXISTS "auth_notifications_read" ON "public"."notifications";
CREATE POLICY "auth_notifications_read" ON "public"."notifications" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE (t.id = notifications.ticket_id))));
DROP POLICY IF EXISTS "auth_notifications_update" ON "public"."notifications";
CREATE POLICY "auth_notifications_update" ON "public"."notifications" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE (t.id = notifications.ticket_id)))) WITH CHECK ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE (t.id = notifications.ticket_id))));
DROP POLICY IF EXISTS "ticket_logs_insert_by_role" ON "public"."ticket_logs";
CREATE POLICY "ticket_logs_insert_by_role" ON "public"."ticket_logs" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((ticket_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM tickets t
  WHERE ((t.id = ticket_logs.ticket_id) AND (t.workspace_id = ( SELECT ctx.workspace_id
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) AND (( SELECT (ctx.is_admin OR ctx.is_attendant)
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) OR (( SELECT ctx.is_technician
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND ((t.technician_id = ( SELECT ctx.actor_employee_id
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) OR ((t.technician_id IS NULL) AND (t.status = ANY (ARRAY['Analise Tecnica'::text, 'Andamento Reparo'::text, 'Teste Final'::text]))))) OR (( SELECT ('tester'::text = ANY (COALESCE(ctx.actor_roles, '{}'::text[])))
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND (ticket_logs.action = ANY (ARRAY['Iniciou Testes'::text, 'Concluiu Testes'::text, 'Reprovou Testes'::text, 'Devolveu para Terceiro'::text])) AND (t.status = ANY (ARRAY['Teste Final'::text, 'Retirada Cliente'::text, 'Andamento Reparo'::text, 'Terceirizado'::text])))))))));
DROP POLICY IF EXISTS "tickets_select_by_role" ON "public"."tickets";
CREATE POLICY "tickets_select_by_role" ON "public"."tickets" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((workspace_id = ( SELECT ctx.workspace_id
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) AND (( SELECT (ctx.is_admin OR ctx.is_attendant)
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) OR (( SELECT ctx.is_technician
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND ((technician_id = ( SELECT ctx.actor_employee_id
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) OR ((technician_id IS NULL) AND (status = ANY (ARRAY['Analise Tecnica'::text, 'Andamento Reparo'::text, 'Teste Final'::text]))))) OR (( SELECT ('tester'::text = ANY (COALESCE(ctx.actor_roles, '{}'::text[])))
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND (status = 'Teste Final'::text)))));
DROP POLICY IF EXISTS "auth_ticket_photos_insert" ON "storage"."objects";
CREATE POLICY "auth_ticket_photos_insert" ON "storage"."objects" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((bucket_id = 'ticket_photos'::text) AND ((storage.foldername(name))[1] = (private.requested_workspace())::text) AND (COALESCE((storage.foldername(name))[2], ''::text) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'::text) AND private.has_workspace_permission(private.requested_workspace(), 'ticket_photo_write'::text)));
REVOKE ALL ON public.notifications FROM authenticated;
DO $$ DECLARE r record;BEGIN FOR r IN SELECT attname FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attnum>0 AND NOT attisdropped LOOP EXECUTE format('REVOKE ALL (%I) ON public.notifications FROM authenticated',r.attname);END LOOP;END $$;
GRANT SELECT,INSERT,UPDATE,DELETE,MAINTAIN ON public.notifications TO authenticated;
DROP FUNCTION IF EXISTS public.conclude_ticket_test(uuid,text,jsonb);
DROP FUNCTION private.can_upload_ticket_photo(text);
COMMIT;
