CREATE OR REPLACE FUNCTION get_daily_report(p_date_start TEXT DEFAULT NULL, p_date_end TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_workspace_id UUID;
    v_user_id UUID;
    v_start TIMESTAMP;
    v_end TIMESTAMP;
    v_result JSONB;
BEGIN
    -- 1. Secure Workspace Resolution
    v_user_id := auth.uid();

    SELECT workspace_id INTO v_workspace_id
    FROM profiles
    WHERE id = v_user_id;

    IF v_workspace_id IS NULL THEN
        SELECT id INTO v_workspace_id
        FROM workspaces
        WHERE owner_id = v_user_id
        LIMIT 1;
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: Workspace não encontrado para o usuário.';
    END IF;

    -- 2. Date Range Calculation
    IF p_date_start IS NULL OR p_date_start = '' THEN
        v_start := CURRENT_DATE::TIMESTAMP;
    ELSE
        v_start := (p_date_start || ' 00:00:00')::TIMESTAMP;
    END IF;

    IF p_date_end IS NULL OR p_date_end = '' THEN
        v_end := (CURRENT_DATE || ' 23:59:59')::TIMESTAMP;
    ELSE
        v_end := (p_date_end || ' 23:59:59')::TIMESTAMP;
    END IF;

    -- 3. Aggregation (Updated to select all fields needed for getWorkflowStageLabel)
    SELECT jsonb_build_object(
        'counts', (
            SELECT jsonb_build_object(
                'created', (SELECT COUNT(*) FROM tickets WHERE workspace_id = v_workspace_id AND created_at BETWEEN v_start AND v_end),
                'repair_success', (SELECT COUNT(*) FROM tickets WHERE workspace_id = v_workspace_id AND repair_end_at BETWEEN v_start AND v_end AND repair_successful = true),
                'repair_fail', (SELECT COUNT(*) FROM tickets WHERE workspace_id = v_workspace_id AND repair_end_at BETWEEN v_start AND v_end AND repair_successful = false),
                'budget_sent', (SELECT COUNT(*) FROM tickets WHERE workspace_id = v_workspace_id AND budget_sent_at BETWEEN v_start AND v_end),
                'budget_approved', (SELECT COUNT(*) FROM ticket_logs l JOIN tickets t ON l.ticket_id = t.id WHERE t.workspace_id = v_workspace_id AND l.action = 'Aprovou Orçamento' AND l.created_at BETWEEN v_start AND v_end),
                'budget_rejected', (SELECT COUNT(*) FROM ticket_logs l JOIN tickets t ON l.ticket_id = t.id WHERE t.workspace_id = v_workspace_id AND l.action = 'Negou Orçamento' AND l.created_at BETWEEN v_start AND v_end),
                'test_approved', (SELECT COUNT(*) FROM ticket_logs l JOIN tickets t ON l.ticket_id = t.id WHERE t.workspace_id = v_workspace_id AND l.action = 'Concluiu Testes' AND l.created_at BETWEEN v_start AND v_end),
                'test_rejected', (SELECT COUNT(*) FROM ticket_logs l JOIN tickets t ON l.ticket_id = t.id WHERE t.workspace_id = v_workspace_id AND l.action = 'Reprovou Testes' AND l.created_at BETWEEN v_start AND v_end),
                'outsourced_sent', (SELECT COUNT(*) FROM ticket_logs l JOIN tickets t ON l.ticket_id = t.id WHERE t.workspace_id = v_workspace_id AND l.action = 'Enviou Terceirizado' AND l.created_at BETWEEN v_start AND v_end)
            )
        ),
        'lists', (
            SELECT jsonb_build_object(
                'arrivals', (
                    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    FROM (
                        SELECT id, client_name, device_model, os_number, created_at, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        FROM tickets
                        WHERE workspace_id = v_workspace_id AND created_at BETWEEN v_start AND v_end
                        ORDER BY created_at DESC
                    ) t
                ),
                'delivered', (
                    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    FROM (
                        SELECT id, client_name, device_model, os_number, delivered_at, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        FROM tickets
                        WHERE workspace_id = v_workspace_id AND delivered_at BETWEEN v_start AND v_end
                        ORDER BY delivered_at DESC
                    ) t
                ),
                'overdue_analysis', (
                    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    FROM (
                        SELECT id, client_name, device_model, os_number, analysis_deadline, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        FROM tickets
                        WHERE workspace_id = v_workspace_id
                          AND status = 'Analise Tecnica'
                          AND analysis_deadline < NOW()
                        ORDER BY analysis_deadline ASC
                    ) t
                ),
                'overdue_repair', (
                    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    FROM (
                        SELECT id, client_name, device_model, os_number, deadline, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        FROM tickets
                        WHERE workspace_id = v_workspace_id
                          AND status = 'Andamento Reparo'
                          AND deadline < NOW()
                        ORDER BY deadline ASC
                    ) t
                ),
                'technicians', (
                    SELECT COALESCE(jsonb_agg(row_to_json(stat)), '[]'::jsonb)
                    FROM (
                        SELECT
                            e.name as name,
                            COUNT(*) FILTER (WHERE t.repair_successful = true) as success,
                            COUNT(*) FILTER (WHERE t.repair_successful = false) as fail,
                            CASE
                                WHEN COUNT(*) > 0 THEN ROUND((COUNT(*) FILTER (WHERE t.repair_successful = true)::numeric / COUNT(*)::numeric) * 100, 1)
                                ELSE 0
                            END as rate
                        FROM employees e
                        JOIN tickets t ON t.technician_id = e.id
                        WHERE e.workspace_id = v_workspace_id
                          AND t.repair_end_at BETWEEN v_start AND v_end
                          AND e.roles::text ILIKE '%tecnico%'
                        GROUP BY e.id, e.name
                    ) stat
                )
            )
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Permissions
REVOKE ALL ON FUNCTION get_daily_report(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_daily_report(TEXT, TEXT) TO authenticated;

-- Reload Schema
NOTIFY pgrst, 'reload schema';
