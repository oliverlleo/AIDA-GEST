-- Configurações operacionais por workspace.
-- Mantém compatibilidade com tracker_config antigo e aplica as regras no banco.

CREATE OR REPLACE FUNCTION public.aida_config_bool(
    p_config jsonb,
    p_group text,
    p_key text,
    p_default boolean
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_catalog
AS $$
    SELECT CASE lower(COALESCE(p_config -> p_group ->> p_key, ''))
        WHEN 'true' THEN true
        WHEN 'false' THEN false
        ELSE p_default
    END;
$$;

CREATE OR REPLACE FUNCTION public.aida_ticket_field_mode(
    p_config jsonb,
    p_key text,
    p_legacy_required boolean DEFAULT false
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_mode text;
BEGIN
    IF p_key IN ('client_name', 'os_number', 'device_model') THEN
        RETURN 'required';
    END IF;

    v_mode := p_config -> 'ticket_field_modes' ->> p_key;
    IF v_mode IN ('disabled', 'optional', 'required') THEN
        RETURN v_mode;
    END IF;

    IF lower(COALESCE(p_config ->> 'enable_required_ticket_fields', 'false')) = 'true' THEN
        RETURN CASE
            WHEN lower(COALESCE(p_config -> 'required_ticket_fields' ->> p_key, 'false')) = 'true'
                THEN 'required'
            ELSE 'optional'
        END;
    END IF;

    RETURN CASE WHEN p_legacy_required THEN 'required' ELSE 'optional' END;
END;
$$;

REVOKE ALL ON FUNCTION public.aida_config_bool(jsonb, text, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aida_ticket_field_mode(jsonb, text, boolean) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.update_workspace_tracker_config(p_config jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_ctx record;
    v_config jsonb;
    v_modes jsonb;
    v_value text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    IF NOT COALESCE(v_ctx.is_admin, false) THEN
        RAISE EXCEPTION 'Acesso negado: somente administradores podem alterar o gerenciamento.';
    END IF;

    IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
        RAISE EXCEPTION 'Configuração inválida.';
    END IF;

    v_modes := COALESCE(p_config -> 'ticket_field_modes', '{}'::jsonb);
    IF jsonb_typeof(v_modes) <> 'object' THEN
        RAISE EXCEPTION 'Configuração de campos inválida.';
    END IF;

    FOR v_value IN SELECT value #>> '{}' FROM jsonb_each(v_modes)
    LOOP
        IF v_value NOT IN ('disabled', 'optional', 'required') THEN
            RAISE EXCEPTION 'Modo de campo inválido: %.', v_value;
        END IF;
    END LOOP;

    IF COALESCE(p_config -> 'workflow' ->> 'delivery_mode', 'complete') NOT IN ('complete', 'simple') THEN
        RAISE EXCEPTION 'Modo de retirada/entrega inválido.';
    END IF;

    IF NOT public.aida_config_bool(p_config, 'workflow', 'parts_control', true)
       AND EXISTS (
            SELECT 1
            FROM public.tickets t
            WHERE t.workspace_id = v_ctx.workspace_id
              AND t.deleted_at IS NULL
              AND (
                    t.status = 'Compra Peca'
                    OR t.repair_paused_at IS NOT NULL
                    OR (t.parts_status IN ('Pendente', 'Comprado') AND t.status <> 'Finalizado')
              )
       ) THEN
        RAISE EXCEPTION 'Não é possível desativar Compra de Peças: existem OS em compra ou reparos pausados. Conclua essas OS primeiro.';
    END IF;

    v_config := p_config || jsonb_build_object(
        'ticket_field_modes',
        v_modes || jsonb_build_object(
            'client_name', 'required',
            'os_number', 'required',
            'device_model', 'required'
        )
    );

    UPDATE public.workspaces
    SET tracker_config = v_config
    WHERE id = v_ctx.workspace_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Workspace não encontrado.';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_workspace_tracker_config(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_workspace_tracker_config(jsonb) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.validate_ticket_requirements()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_config jsonb := '{}'::jsonb;
    v_missing text[] := ARRAY[]::text[];
    v_insert boolean := TG_OP = 'INSERT';
BEGIN
    SELECT COALESCE(w.tracker_config, '{}'::jsonb)
      INTO v_config
      FROM public.workspaces w
     WHERE w.id = NEW.workspace_id;

    IF public.aida_ticket_field_mode(v_config, 'client_name', true) = 'required'
       AND (NEW.client_name IS NULL OR btrim(NEW.client_name) = '')
       AND (v_insert OR NOT (OLD.client_name IS NULL OR btrim(OLD.client_name) = ''))
    THEN v_missing := array_append(v_missing, 'Cliente'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'os_number', true) = 'required'
       AND (NEW.os_number IS NULL OR btrim(NEW.os_number) = '')
       AND (v_insert OR NOT (OLD.os_number IS NULL OR btrim(OLD.os_number) = ''))
    THEN v_missing := array_append(v_missing, 'Nº OS'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'device_model', true) = 'required'
       AND (NEW.device_model IS NULL OR btrim(NEW.device_model) = '')
       AND (v_insert OR NOT (OLD.device_model IS NULL OR btrim(OLD.device_model) = ''))
    THEN v_missing := array_append(v_missing, 'Modelo'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'contact_info', false) = 'required'
       AND (NEW.contact_info IS NULL OR btrim(NEW.contact_info) = '')
       AND (v_insert OR NOT (OLD.contact_info IS NULL OR btrim(OLD.contact_info) = ''))
    THEN v_missing := array_append(v_missing, 'Contato'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'serial_number', false) = 'required'
       AND (NEW.serial_number IS NULL OR btrim(NEW.serial_number) = '')
       AND (v_insert OR NOT (OLD.serial_number IS NULL OR btrim(OLD.serial_number) = ''))
    THEN v_missing := array_append(v_missing, 'Nº Série / IMEI'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'priority', false) = 'required'
       AND (NEW.priority IS NULL OR btrim(NEW.priority) = '')
       AND (v_insert OR NOT (OLD.priority IS NULL OR btrim(OLD.priority) = ''))
    THEN v_missing := array_append(v_missing, 'Prioridade'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'device_condition', false) = 'required'
       AND (NEW.device_condition IS NULL OR btrim(NEW.device_condition) = '')
       AND (v_insert OR NOT (OLD.device_condition IS NULL OR btrim(OLD.device_condition) = ''))
    THEN v_missing := array_append(v_missing, 'Situação do Aparelho'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'defect_reported', true) = 'required'
       AND (NEW.defect_reported IS NULL OR btrim(NEW.defect_reported) = '')
       AND (v_insert OR NOT (OLD.defect_reported IS NULL OR btrim(OLD.defect_reported) = ''))
    THEN v_missing := array_append(v_missing, 'Defeito Relatado'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'analysis_deadline', true) = 'required'
       AND NOT (v_insert AND NEW.budget_status = 'Aprovado' AND NEW.status IN ('Andamento Reparo', 'Compra Peca'))
       AND NEW.analysis_deadline IS NULL
       AND (v_insert OR OLD.analysis_deadline IS NOT NULL)
    THEN v_missing := array_append(v_missing, 'Prazo de Análise'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'deadline', true) = 'required'
       AND NEW.deadline IS NULL
       AND (v_insert OR OLD.deadline IS NOT NULL)
    THEN v_missing := array_append(v_missing, 'Prazo de Entrega'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'responsible', true) = 'required' THEN
        IF NEW.is_outsourced IS TRUE AND NEW.outsourced_company_id IS NULL
           AND (v_insert OR OLD.outsourced_company_id IS NOT NULL OR OLD.is_outsourced IS DISTINCT FROM true)
        THEN v_missing := array_append(v_missing, 'Empresa Parceira');
        ELSIF COALESCE(NEW.is_outsourced, false) IS FALSE AND NEW.technician_id IS NULL
           AND (v_insert OR OLD.technician_id IS NOT NULL OR OLD.is_outsourced IS DISTINCT FROM false)
        THEN v_missing := array_append(v_missing, 'Técnico Responsável');
        END IF;
    END IF;

    IF public.aida_ticket_field_mode(v_config, 'checklist_entry', false) = 'required'
       AND (NEW.checklist_data IS NULL OR jsonb_typeof(NEW.checklist_data) <> 'array' OR NEW.checklist_data = '[]'::jsonb)
       AND (v_insert OR NOT (OLD.checklist_data IS NULL OR jsonb_typeof(OLD.checklist_data) <> 'array' OR OLD.checklist_data = '[]'::jsonb))
    THEN v_missing := array_append(v_missing, 'Checklist de Entrada'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'checklist_exit', false) = 'required'
       AND (NEW.checklist_final_data IS NULL OR jsonb_typeof(NEW.checklist_final_data) <> 'array' OR NEW.checklist_final_data = '[]'::jsonb)
       AND (v_insert OR NOT (OLD.checklist_final_data IS NULL OR jsonb_typeof(OLD.checklist_final_data) <> 'array' OR OLD.checklist_final_data = '[]'::jsonb))
    THEN v_missing := array_append(v_missing, 'Checklist de Saída'); END IF;

    IF public.aida_ticket_field_mode(v_config, 'photos', false) = 'required'
       AND (NEW.photos_urls IS NULL OR jsonb_typeof(NEW.photos_urls) <> 'array' OR NEW.photos_urls = '[]'::jsonb)
       AND (v_insert OR NOT (OLD.photos_urls IS NULL OR jsonb_typeof(OLD.photos_urls) <> 'array' OR OLD.photos_urls = '[]'::jsonb))
    THEN v_missing := array_append(v_missing, 'Fotos'); END IF;

    IF array_length(v_missing, 1) > 0 THEN
        RAISE EXCEPTION 'Campos obrigatórios não preenchidos: %', array_to_string(v_missing, ', ');
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_configurable_ticket_workflow()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_config jsonb := '{}'::jsonb;
BEGIN
    SELECT COALESCE(w.tracker_config, '{}'::jsonb)
      INTO v_config
      FROM public.workspaces w
     WHERE w.id = NEW.workspace_id;

    IF NEW.status = 'Compra Peca'
       AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'Compra Peca')
       AND NOT public.aida_config_bool(v_config, 'workflow', 'parts_control', true)
    THEN
        RAISE EXCEPTION 'O controle de compra de peças está desativado.';
    END IF;

    IF NEW.status = 'Teste Final'
       AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'Teste Final')
       AND NOT public.aida_config_bool(v_config, 'workflow', 'final_test', true)
    THEN
        NEW.status := 'Retirada Cliente';
    END IF;

    IF COALESCE(NEW.priority_requested, false)
       AND (TG_OP = 'INSERT' OR NOT COALESCE(OLD.priority_requested, false))
       AND NOT public.aida_config_bool(v_config, 'workflow', 'priority_requests', true)
    THEN
        RAISE EXCEPTION 'O pedido de prioridade está desativado.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_configurable_ticket_workflow ON public.tickets;
CREATE TRIGGER trg_enforce_configurable_ticket_workflow
BEFORE INSERT OR UPDATE ON public.tickets
FOR EACH ROW EXECUTE FUNCTION public.enforce_configurable_ticket_workflow();

CREATE OR REPLACE FUNCTION public.enforce_configurable_appointment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_config jsonb := '{}'::jsonb;
    v_field text;
    v_disabled boolean;
    v_changes_active_appointment boolean;
BEGIN
    SELECT COALESCE(w.tracker_config, '{}'::jsonb)
      INTO v_config
      FROM public.workspaces w
     WHERE w.id = NEW.workspace_id;

    v_field := CASE WHEN NEW.appointment_type = 'repair' THEN 'repair_schedule' ELSE 'analysis_schedule' END;
    v_disabled := NOT public.aida_config_bool(v_config, 'modules', 'agenda', true)
        OR public.aida_ticket_field_mode(v_config, v_field, false) = 'disabled';

    v_changes_active_appointment := TG_OP = 'INSERT'
        OR OLD.technician_id IS DISTINCT FROM NEW.technician_id
        OR OLD.scheduled_start IS DISTINCT FROM NEW.scheduled_start
        OR OLD.scheduled_end IS DISTINCT FROM NEW.scheduled_end
        OR OLD.appointment_type IS DISTINCT FROM NEW.appointment_type
        OR (OLD.status NOT IN ('scheduled', 'in_progress') AND NEW.status IN ('scheduled', 'in_progress'));

    IF v_disabled AND NEW.status IN ('scheduled', 'in_progress') AND v_changes_active_appointment THEN
        RAISE EXCEPTION 'Este tipo de agendamento está desativado no gerenciamento.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_configurable_appointment ON public.ticket_appointments;
CREATE TRIGGER trg_enforce_configurable_appointment
BEFORE INSERT OR UPDATE ON public.ticket_appointments
FOR EACH ROW EXECUTE FUNCTION public.enforce_configurable_appointment();

-- Funções de trigger não são endpoints RPC e não devem ser executáveis pelo cliente.
REVOKE ALL ON FUNCTION public.validate_ticket_requirements() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_configurable_ticket_workflow() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_configurable_appointment() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_client_ticket_details_public_configurable(
    p_ticket_id uuid,
    p_public_token uuid
)
RETURNS TABLE(
    id uuid,
    os_number text,
    device_model text,
    status text,
    deadline timestamptz,
    priority_requested boolean,
    pickup_available boolean,
    created_at timestamptz,
    whatsapp_number text,
    tracker_config jsonb,
    delivery_method text,
    carrier_name text,
    tracking_code text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
    SELECT d.*
    FROM public.tickets t
    JOIN public.workspaces w ON w.id = t.workspace_id
    CROSS JOIN LATERAL public.get_client_ticket_details_public(p_ticket_id, p_public_token) d
    WHERE t.id = p_ticket_id
      AND t.public_token = p_public_token
      AND t.deleted_at IS NULL
      AND public.aida_config_bool(COALESCE(w.tracker_config, '{}'::jsonb), 'modules', 'public_tracker', true);
$$;

REVOKE ALL ON FUNCTION public.get_client_ticket_details_public_configurable(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public_configurable(uuid, uuid) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.start_ticket_analysis(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.start_repair_timer(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
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
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
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
$$;

CREATE OR REPLACE FUNCTION public.pause_repair_for_parts(p_ticket_id uuid, p_parts_needed text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.complete_repair_with_timer(p_ticket_id uuid, p_success boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.start_ticket_analysis(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_repair_timer(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pause_repair_for_parts(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_repair_with_timer(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_ticket_analysis(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_repair_timer(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pause_repair_for_parts(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_repair_with_timer(uuid, boolean) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.resume_repair_after_parts(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.resume_repair_after_parts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resume_repair_after_parts(uuid) TO anon, authenticated;

