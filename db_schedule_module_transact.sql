BEGIN;

CREATE OR REPLACE FUNCTION public.create_ticket_with_optional_analysis_schedule(
    p_ticket jsonb,
    p_appointment jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_ctx record;
    v_ws_id uuid;
    v_ticket_id uuid;
    v_status text := 'Aberto';
    v_entry_date timestamptz := now();
    v_tracker_config jsonb;
    v_is_analysis_required boolean := false;
    v_technician_id uuid;
    v_outsourced_company_id uuid;
    v_created_by uuid;
    v_created_by_name text;
    v_appointment_id uuid;
    v_app_tech_id uuid;
    v_app_type text;
    v_app_start timestamptz;
    v_app_end timestamptz;
    v_app_notes text;
    v_app_res jsonb;
BEGIN
    -- 1. Resolver contexto no servidor
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    -- Definir o autor
    IF v_ctx.actor_kind = 'employee' THEN
        v_created_by := v_ctx.actor_employee_id;
        v_created_by_name := v_ctx.actor_name;
    ELSE
        v_created_by := v_ctx.actor_user_id;
        v_created_by_name := v_ctx.actor_name;
    END IF;

    -- 2. Ler tracker_config do workspace
    SELECT tracker_config INTO v_tracker_config
    FROM public.workspaces
    WHERE id = v_ws_id;

    IF v_tracker_config IS NOT NULL AND v_tracker_config ? 'required_ticket_fields' THEN
        v_is_analysis_required := COALESCE((v_tracker_config->'required_ticket_fields'->>'analysis_schedule')::boolean, false);
    END IF;

    -- 3. Validar e sanitizar dependências de foreign keys do payload
    IF p_ticket ? 'technician_id' AND (p_ticket->>'technician_id') IS NOT NULL THEN
        v_technician_id := (p_ticket->>'technician_id')::uuid;
        IF NOT EXISTS (SELECT 1 FROM public.employees WHERE id = v_technician_id AND workspace_id = v_ws_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Técnico não encontrado ou não pertence ao workspace.';
        END IF;
    END IF;

    IF p_ticket ? 'outsourced_company_id' AND (p_ticket->>'outsourced_company_id') IS NOT NULL THEN
        v_outsourced_company_id := (p_ticket->>'outsourced_company_id')::uuid;
        IF NOT EXISTS (SELECT 1 FROM public.outsourced_companies WHERE id = v_outsourced_company_id AND workspace_id = v_ws_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Empresa parceira não encontrada ou não pertence ao workspace.';
        END IF;
    END IF;

    -- 4. Inserir ticket via whitelist explícita de campos seguros
    INSERT INTO public.tickets (
        workspace_id,
        created_by,
        created_by_name,
        status,
        entry_date,
        client_name,
        contact_info,
        os_number,
        priority,
        device_model,
        serial_number,
        defect_reported,
        device_condition,
        checklist_data,
        photos_urls,
        analysis_deadline,
        deadline,
        delivery_method,
        carrier_name,
        tracking_code,
        is_outsourced,
        outsourced_company_id,
        outsourced_deadline,
        technician_id
    ) VALUES (
        v_ws_id,
        v_created_by,
        v_created_by_name,
        v_status,
        v_entry_date,
        NULLIF(p_ticket->>'client_name', ''),
        NULLIF(p_ticket->>'contact_info', ''),
        NULLIF(p_ticket->>'os_number', ''),
        COALESCE(p_ticket->>'priority', 'Normal'),
        NULLIF(p_ticket->>'device_model', ''),
        NULLIF(p_ticket->>'serial_number', ''),
        NULLIF(p_ticket->>'defect_reported', ''),
        NULLIF(p_ticket->>'device_condition', ''),
        CASE WHEN p_ticket ? 'checklist_data' AND jsonb_typeof(p_ticket->'checklist_data') = 'array' THEN p_ticket->'checklist_data' ELSE '[]'::jsonb END,
        CASE
            WHEN p_ticket ? 'photos_urls' AND jsonb_typeof(p_ticket->'photos_urls') = 'array' THEN
                ARRAY(SELECT jsonb_array_elements_text(p_ticket->'photos_urls'))
            ELSE '{}'::text[]
        END,
        (p_ticket->>'analysis_deadline')::timestamptz,
        (p_ticket->>'deadline')::timestamptz,
        NULLIF(p_ticket->>'delivery_method', ''),
        NULLIF(p_ticket->>'carrier_name', ''),
        NULLIF(p_ticket->>'tracking_code', ''),
        COALESCE((p_ticket->>'is_outsourced')::boolean, false),
        v_outsourced_company_id,
        (p_ticket->>'outsourced_deadline')::timestamptz,
        v_technician_id
    ) RETURNING id INTO v_ticket_id;

    -- 5. Se veio p_appointment, criar usando a RPC existente
    IF p_appointment IS NOT NULL AND jsonb_typeof(p_appointment) = 'object' THEN
        v_app_tech_id := COALESCE((p_appointment->>'technician_id')::uuid, v_technician_id);
        v_app_type := COALESCE(p_appointment->>'appointment_type', 'analysis');
        v_app_start := (p_appointment->>'scheduled_start')::timestamptz;
        v_app_end := (p_appointment->>'scheduled_end')::timestamptz;
        v_app_notes := p_appointment->>'notes';

        IF v_app_tech_id IS NULL THEN
            RAISE EXCEPTION 'technician_id é obrigatório para criar um agendamento.';
        END IF;

        v_app_res := public.create_ticket_appointment(
            v_ticket_id,
            v_app_tech_id,
            v_app_type,
            v_app_start,
            v_app_end,
            v_app_notes
        );

        v_appointment_id := (v_app_res->>'appointment_id')::uuid;
    END IF;

    -- 6. Validar a obrigatoriedade da configuração (analysis_schedule) no final da operação
    IF v_is_analysis_required THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.ticket_appointments
            WHERE ticket_id = v_ticket_id
              AND workspace_id = v_ws_id
              AND deleted_at IS NULL
              AND status != 'cancelled'
              AND appointment_type = 'analysis'
        ) THEN
            RAISE EXCEPTION 'A configuração do workspace exige um agendamento de análise (analysis_schedule) para este chamado.';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'ticket_id', v_ticket_id,
        'appointment_id', v_appointment_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) TO authenticated, anon;

COMMIT;
