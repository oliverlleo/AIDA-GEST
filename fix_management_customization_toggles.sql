-- Seletores funcionais dos grupos de personalização do Gerenciamento.
-- Desligado: banco e front-end usam os padrões seguros do sistema.

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
    SELECT CASE
        WHEN p_group = 'workflow'
             AND p_key IN ('parts_control', 'analysis_timer', 'repair_timer', 'priority_requests')
             AND lower(COALESCE(p_config -> 'customization' ->> 'workflow', 'false')) <> 'true'
            THEN p_default
        WHEN p_group = 'modules'
             AND lower(COALESCE(p_config -> 'customization' ->> 'modules', 'false')) <> 'true'
            THEN p_default
        WHEN p_group = 'overview_sections'
             AND lower(COALESCE(p_config -> 'customization' ->> 'overview', 'false')) <> 'true'
            THEN p_default
        ELSE CASE lower(COALESCE(p_config -> p_group ->> p_key, ''))
            WHEN 'true' THEN true
            WHEN 'false' THEN false
            ELSE p_default
        END
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

    IF lower(COALESCE(p_config -> 'customization' ->> 'ticket_fields', 'false')) = 'true' THEN
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
    v_customization jsonb;
    v_modes jsonb;
    v_value text;
    v_key text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    IF NOT COALESCE(v_ctx.is_admin, false) THEN
        RAISE EXCEPTION 'Acesso negado: somente administradores podem alterar o gerenciamento.';
    END IF;

    IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
        RAISE EXCEPTION 'Configuração inválida.';
    END IF;

    v_customization := COALESCE(p_config -> 'customization', '{}'::jsonb);
    IF jsonb_typeof(v_customization) <> 'object' THEN
        RAISE EXCEPTION 'Configuração dos seletores inválida.';
    END IF;

    FOREACH v_key IN ARRAY ARRAY['workflow', 'modules', 'ticket_fields', 'overview']
    LOOP
        IF v_customization -> v_key IS NOT NULL
           AND jsonb_typeof(v_customization -> v_key) <> 'boolean' THEN
            RAISE EXCEPTION 'O seletor % deve ser verdadeiro ou falso.', v_key;
        END IF;
    END LOOP;

    v_customization := jsonb_build_object(
        'workflow', lower(COALESCE(v_customization ->> 'workflow', 'false')) = 'true',
        'modules', lower(COALESCE(v_customization ->> 'modules', 'false')) = 'true',
        'ticket_fields', lower(COALESCE(v_customization ->> 'ticket_fields', 'false')) = 'true',
        'overview', lower(COALESCE(v_customization ->> 'overview', 'false')) = 'true'
    );
    v_config := jsonb_set(p_config, '{customization}', v_customization, true);

    IF NOT (v_customization ->> 'workflow')::boolean THEN
        v_config := jsonb_set(
            v_config,
            '{workflow}',
            COALESCE(v_config -> 'workflow', '{}'::jsonb) || jsonb_build_object(
                'parts_control', true,
                'analysis_timer', true,
                'repair_timer', true,
                'delivery_mode', 'complete',
                'priority_requests', true
            ),
            true
        );
    END IF;

    IF NOT (v_customization ->> 'modules')::boolean THEN
        v_config := jsonb_set(v_config, '{modules}', jsonb_build_object(
            'agenda', true,
            'suppliers', true,
            'manager_dashboard', true,
            'public_tracker', true
        ), true);
    END IF;

    IF NOT (v_customization ->> 'ticket_fields')::boolean THEN
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
    END IF;

    IF NOT (v_customization ->> 'overview')::boolean THEN
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
    END IF;

    IF jsonb_typeof(COALESCE(v_config -> 'workflow', '{}'::jsonb)) <> 'object'
       OR jsonb_typeof(COALESCE(v_config -> 'modules', '{}'::jsonb)) <> 'object'
       OR jsonb_typeof(COALESCE(v_config -> 'overview_sections', '{}'::jsonb)) <> 'object' THEN
        RAISE EXCEPTION 'Configuração de gerenciamento inválida.';
    END IF;

    v_modes := COALESCE(v_config -> 'ticket_field_modes', '{}'::jsonb);
    IF jsonb_typeof(v_modes) <> 'object' THEN
        RAISE EXCEPTION 'Configuração de campos inválida.';
    END IF;

    FOR v_value IN SELECT value #>> '{}' FROM jsonb_each(v_modes)
    LOOP
        IF v_value NOT IN ('disabled', 'optional', 'required') THEN
            RAISE EXCEPTION 'Modo de campo inválido: %.', v_value;
        END IF;
    END LOOP;

    IF COALESCE(v_config -> 'workflow' ->> 'delivery_mode', 'complete') NOT IN ('complete', 'simple') THEN
        RAISE EXCEPTION 'Modo de retirada/entrega inválido.';
    END IF;

    IF NOT public.aida_config_bool(v_config, 'workflow', 'parts_control', true)
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
