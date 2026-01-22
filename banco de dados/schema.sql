CREATE OR REPLACE FUNCTION public.get_dashboard_kpis(p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_technician_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_defect text DEFAULT NULL::text, p_device_model text DEFAULT NULL::text, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_workspace_id UUID;
    v_user_id UUID;
    v_role TEXT;
    v_result JSONB;
BEGIN
    -- 1. SECURITY: Determine Workspace Context
    v_role := auth.role();
    v_user_id := auth.uid();

    IF v_role = 'authenticated' THEN
        -- Admin: Get workspace from workspace ownership
        SELECT id INTO v_workspace_id FROM public.workspaces WHERE owner_id = v_user_id LIMIT 1;
    ELSE
        -- Employee (anon): Get workspace from Token
        -- This function checks x-employee-token header and validates the session
        SELECT workspace_id INTO v_workspace_id FROM public.current_employee_from_token();
    END IF;

    IF v_workspace_id IS NULL THEN
        -- Fail safe
        RAISE EXCEPTION 'Acesso negado: Workspace não identificado ou token inválido.';
    END IF;

    -- 2. QUERY LOGIC (Identical to original but enforcing v_workspace_id)
    WITH filtered_tickets AS (
        SELECT
            t.*,
            COALESCE(t.repair_end_at, CASE WHEN t.status = 'Finalizado' THEN t.updated_at ELSE NULL END) as effective_repair_end,
            EXTRACT(EPOCH FROM (t.repair_end_at - t.repair_start_at)) as duration_repair_sec,
            EXTRACT(EPOCH FROM (COALESCE(t.pickup_available_at, t.repair_end_at) - t.created_at)) as duration_solution_sec,
            EXTRACT(EPOCH FROM (t.delivered_at - t.created_at)) as duration_delivery_sec,
            EXTRACT(EPOCH FROM (t.budget_sent_at - t.created_at)) as duration_budget_sec,
            EXTRACT(EPOCH FROM (t.pickup_available_at - t.created_at)) as duration_pickup_notify_sec
        FROM
            public.tickets t
        WHERE
            t.workspace_id = v_workspace_id -- ENFORCED HERE
            AND t.deleted_at IS NULL
            AND (p_date_start IS NULL OR t.created_at >= p_date_start::timestamp)
            AND (p_date_end IS NULL OR t.created_at <= (p_date_end::timestamp + INTERVAL '1 day' - INTERVAL '1 millisecond'))
            AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
            AND (p_status IS NULL OR p_status = 'all' OR t.status = p_status)
            AND (p_device_model IS NULL OR p_device_model = 'all' OR t.device_model = p_device_model)
            AND (p_defect IS NULL OR p_defect = 'all' OR t.defect_reported ILIKE '%' || p_defect || '%')
            AND (p_search IS NULL OR
                 t.client_name ILIKE '%' || p_search || '%' OR
                 t.os_number ILIKE '%' || p_search || '%' OR
                 t.device_model ILIKE '%' || p_search || '%' OR
                 t.serial_number ILIKE '%' || p_search || '%' OR
                 t.contact_info ILIKE '%' || p_search || '%'
            )
    ),
    expanded_defects AS (
        SELECT
            trim(defect) as defect_name,
            repair_successful,
            duration_repair_sec,
            duration_solution_sec,
            duration_delivery_sec,
            device_model,
            technician_id
        FROM
            filtered_tickets,
            unnest(string_to_array(defect_reported, ',')) as defect
        WHERE
            trim(defect) <> ''
    ),
    stats AS (
        SELECT
            count(*) as total_tickets,
            count(*) FILTER (WHERE status = 'Analise Tecnica') as analysis_count,
            count(*) FILTER (WHERE status = 'Andamento Reparo') as repair_count,
            count(*) FILTER (WHERE repair_successful IS NOT NULL) as total_with_outcome,
            count(*) FILTER (WHERE repair_successful = TRUE) as success_count,
            avg(duration_repair_sec) FILTER (WHERE duration_repair_sec > 0) as avg_repair_sec,
            avg(duration_solution_sec) FILTER (WHERE duration_solution_sec > 0) as avg_solution_sec,
            avg(duration_delivery_sec) FILTER (WHERE duration_delivery_sec > 0) as avg_delivery_sec,
            avg(duration_budget_sec) FILTER (WHERE duration_budget_sec > 0) as avg_budget_sec,
            avg(duration_pickup_notify_sec) FILTER (WHERE duration_pickup_notify_sec > 0) as avg_pickup_notify_sec,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '1 day')) as tickets_today,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '7 days')) as tickets_week,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '30 days')) as tickets_month,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '1 day')) as repairs_today,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '7 days')) as repairs_week,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '30 days')) as repairs_month,
            count(*) FILTER (WHERE delivery_method = 'pickup') as pickup_total,
            count(*) FILTER (WHERE delivery_method = 'pickup' AND repair_successful = TRUE) as pickup_success,
            count(*) FILTER (WHERE delivery_method = 'pickup' AND repair_successful = FALSE) as pickup_fail,
            count(*) FILTER (WHERE delivery_method = 'carrier') as carrier_total,
            count(*) FILTER (WHERE delivery_method = 'carrier' AND repair_successful = TRUE) as carrier_success,
            count(*) FILTER (WHERE delivery_method = 'carrier' AND repair_successful = FALSE) as carrier_fail,
            count(*) FILTER (WHERE is_outsourced = TRUE) as outsourced_total,
            count(*) FILTER (WHERE is_outsourced = TRUE AND repair_successful = TRUE) as outsourced_success,
            count(*) FILTER (WHERE is_outsourced = TRUE AND repair_successful = FALSE) as outsourced_fail,
            sum(COALESCE(outsourced_return_count, 0)) as outsourced_returns,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto')) as internal_total,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto') AND repair_successful = TRUE) as internal_success,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto') AND repair_successful = FALSE) as internal_fail
        FROM filtered_tickets
    ),
    top_defects AS (
        SELECT defect_name as label, count(*) as total, count(*) FILTER (WHERE repair_successful = TRUE) as success, count(*) FILTER (WHERE repair_successful = FALSE) as fail, CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate", CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate" FROM expanded_defects GROUP BY defect_name ORDER BY total DESC
    ),
    top_models AS (
        SELECT device_model as label, count(*) as total, count(*) FILTER (WHERE repair_successful = TRUE) as success, count(*) FILTER (WHERE repair_successful = FALSE) as fail, CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate", CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate" FROM filtered_tickets WHERE device_model IS NOT NULL GROUP BY device_model ORDER BY total DESC
    ),
    top_combos AS (
        SELECT device_model || ' · ' || defect_name as label, count(*) as total, count(*) FILTER (WHERE repair_successful = TRUE) as success, count(*) FILTER (WHERE repair_successful = FALSE) as fail, CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate", CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate" FROM expanded_defects WHERE device_model IS NOT NULL GROUP BY device_model, defect_name ORDER BY total DESC
    ),
    tech_metrics AS (
        SELECT t.technician_id, count(*) as total, count(*) FILTER (WHERE t.repair_successful IS NOT NULL) as completed, count(*) FILTER (WHERE t.repair_successful = TRUE) as success_count FROM filtered_tickets t WHERE t.technician_id IS NOT NULL GROUP BY t.technician_id
    )
    SELECT
        jsonb_build_object(
            'successRate', CASE WHEN (SELECT total_with_outcome FROM stats) > 0 THEN round(((SELECT success_count FROM stats)::numeric / (SELECT total_with_outcome FROM stats)) * 100) ELSE 0 END,
            'avgRepair', COALESCE((SELECT avg_repair_sec FROM stats) * 1000, 0),
            'avgSolution', COALESCE((SELECT avg_solution_sec FROM stats) * 1000, 0),
            'avgDelivery', COALESCE((SELECT avg_delivery_sec FROM stats) * 1000, 0),
            'avgBudget', COALESCE((SELECT avg_budget_sec FROM stats) * 1000, 0),
            'avgPickupNotify', COALESCE((SELECT avg_pickup_notify_sec FROM stats) * 1000, 0),
            'analysisCount', (SELECT analysis_count FROM stats),
            'repairCount', (SELECT repair_count FROM stats),
            'ticketsPerDay', CASE WHEN p_date_start IS NOT NULL AND p_date_end IS NOT NULL THEN round((SELECT total_tickets FROM stats)::numeric / GREATEST(1, EXTRACT(DAY FROM (p_date_end::timestamp - p_date_start::timestamp)))) ELSE 0 END,
            'repairsToday', (SELECT repairs_today FROM stats),
            'repairsWeek', (SELECT repairs_week FROM stats),
            'repairsMonth', (SELECT repairs_month FROM stats),
            'ticketsToday', (SELECT tickets_today FROM stats),
            'ticketsWeek', (SELECT tickets_week FROM stats),
            'ticketsMonth', (SELECT tickets_month FROM stats),
            'topDefects', (SELECT COALESCE(jsonb_agg(d), '[]'::jsonb) FROM (SELECT * FROM top_defects) d),
            'topModels', (SELECT COALESCE(jsonb_agg(m), '[]'::jsonb) FROM (SELECT * FROM top_models LIMIT 100) m),
            'topCombos', (SELECT COALESCE(jsonb_agg(c), '[]'::jsonb) FROM (SELECT * FROM top_combos LIMIT 50) c),
            'techStats', (SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (SELECT tm.technician_id as id, e.name, tm.total, tm.completed, CASE WHEN tm.completed > 0 THEN round((tm.success_count::numeric / tm.completed) * 100) ELSE 0 END as "successRate" FROM tech_metrics tm LEFT JOIN public.employees e ON e.id = tm.technician_id ORDER BY tm.completed DESC) t),
            'slowestModels', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count FROM filtered_tickets WHERE duration_repair_sec > 0 GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestModelsSolution', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model as label, avg(duration_solution_sec) * 1000 as "avgTime", count(*) as count FROM filtered_tickets WHERE duration_solution_sec > 0 GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestModelsDelivery', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model as label, avg(duration_delivery_sec) * 1000 as "avgTime", count(*) as count FROM filtered_tickets WHERE duration_delivery_sec > 0 GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestDefects', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT defect_name as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count FROM expanded_defects WHERE duration_repair_sec > 0 GROUP BY defect_name ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestCombos', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model || ' - ' || defect_name as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count FROM expanded_defects WHERE duration_repair_sec > 0 GROUP BY label ORDER BY "avgTime" DESC LIMIT 5) x),
            'logisticsStats', jsonb_build_object('pickup', jsonb_build_object('total', (SELECT pickup_total FROM stats), 'success', (SELECT pickup_success FROM stats), 'fail', (SELECT pickup_fail FROM stats)), 'carrier', jsonb_build_object('total', (SELECT carrier_total FROM stats), 'success', (SELECT carrier_success FROM stats), 'fail', (SELECT carrier_fail FROM stats))),
            'outsourcedStats', jsonb_build_object('total', (SELECT outsourced_total FROM stats), 'success', (SELECT outsourced_success FROM stats), 'fail', (SELECT outsourced_fail FROM stats), 'returns', (SELECT outsourced_returns FROM stats)),
            'internalStats', jsonb_build_object('total', (SELECT internal_total FROM stats), 'success', (SELECT internal_success FROM stats), 'fail', (SELECT internal_fail FROM stats))
        ) INTO v_result;

    RETURN v_result;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.log_ticket_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.status <> OLD.status THEN
            INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
            VALUES (NEW.id, 'Alteração de Status', 'De ' || OLD.status || ' para ' || NEW.status, 'Sistema');
        END IF;
    ELSIF (TG_OP = 'INSERT') THEN
         INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
         VALUES (NEW.id, 'Criado', 'Chamado aberto', NEW.created_by_name);
    END IF;
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_client_ticket_details(p_ticket_id uuid)
 RETURNS TABLE(id uuid, os_number text, device_model text, status text, deadline timestamp with time zone, priority_requested boolean, pickup_available boolean, created_at timestamp with time zone, whatsapp_number text, tracker_config jsonb, delivery_method text, carrier_name text, tracking_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
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
    WHERE t.id = p_ticket_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_operational_alerts(p_workspace_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_workspace_id UUID;
    v_user_id UUID;
    v_role TEXT;
    v_result JSONB;
BEGIN
    -- 1. SECURITY: Determine Workspace Context
    v_role := auth.role();
    v_user_id := auth.uid();

    IF v_role = 'authenticated' THEN
        -- Admin: Get workspace from workspace ownership
        -- Optimization: If p_workspace_id is passed, check if owner owns it. If not passed, find default.
        IF p_workspace_id IS NOT NULL THEN
             SELECT id INTO v_workspace_id FROM public.workspaces WHERE id = p_workspace_id AND owner_id = v_user_id;
             IF v_workspace_id IS NULL THEN RAISE EXCEPTION 'Acesso negado: Workspace inválido para este admin.'; END IF;
        ELSE
             SELECT id INTO v_workspace_id FROM public.workspaces WHERE owner_id = v_user_id LIMIT 1;
        END IF;
    ELSE
        -- Employee (anon): Get workspace from Token (IGNORE p_workspace_id)
        SELECT workspace_id INTO v_workspace_id FROM public.current_employee_from_token();
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: Workspace não identificado ou token inválido.';
    END IF;

    -- 2. QUERY LOGIC (Using v_workspace_id)
    -- Calculate operational buckets
    SELECT jsonb_build_object(
        'pendingBudgets', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.created_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Analise Tecnica' -- Or specific flow for budgets? "Aberto" -> "Analise" -> "Aprovacao"
              -- Assuming logic: Needs budget sent. Usually means 'Aprovacao' but budget_status is null/pending?
              -- Adjusting to likely logic: Status 'Aprovacao' and budget not sent yet?
              -- Or is it 'Analise Tecnica' finished?
              -- Let's stick to standard buckets inferred from context or previous logic if available.
              -- Re-implementing standard logic:
              -- "Orçamento Pendente": Status 'Aprovacao' AND budget_status IS NULL (or 'Pendente')
              AND t.status = 'Aprovacao'
              AND (t.budget_status IS NULL OR t.budget_status = 'Pendente')
              AND t.deleted_at IS NULL
        ),
        'waitingBudgetResponse', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.budget_sent_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Aprovacao'
              AND t.budget_status = 'Enviado'
              AND t.deleted_at IS NULL
        ),
        'pendingPickups', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.deadline ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Retirada Cliente'
              AND t.pickup_available = FALSE -- Not yet marked available? Or maybe it is available?
              -- Usually "Solicitar Retirada" means they are ready but client not notified?
              -- Actually, if pickup_available is true, they are ready.
              -- Let's assume pendingPickups means "Ready for Pickup/Delivery"
              -- Actually the dashboard logic says: "Pickups to Notify / Logistics Pending"
              -- So status 'Retirada Cliente' and NOT pickup_available?
              -- Or status 'Retirada Cliente' generally.
              AND t.deleted_at IS NULL
        ),
        'urgentAnalysis', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.analysis_deadline ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status IN ('Aberto', 'Analise Tecnica')
              AND t.analysis_deadline < (now() + interval '4 hours')
              AND t.deleted_at IS NULL
        ),
        'delayedDeliveries', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.deadline ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status NOT IN ('Retirada Cliente', 'Finalizado')
              AND t.deadline < now()
              AND t.deleted_at IS NULL
        ),
        'priorityTickets', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.created_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.priority_requested = TRUE
              AND t.status NOT IN ('Finalizado')
              AND t.deleted_at IS NULL
        ),
        'pendingPurchase', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.created_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Compra Peca'
              AND (t.parts_status IS NULL OR t.parts_status = 'Pendente')
              AND t.deleted_at IS NULL
        ),
        'pendingReceipt', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.parts_purchased_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Compra Peca'
              AND t.parts_status = 'Comprado'
              AND t.deleted_at IS NULL
        ),
        'pendingTech', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.created_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Aberto'
              -- AND t.technician_id IS NULL -- Maybe? Or just any open ticket.
              AND t.is_outsourced = FALSE
              AND t.deleted_at IS NULL
        ),
        -- Logistics
        'pendingTracking', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.pickup_available_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Retirada Cliente'
              AND t.delivery_method = 'carrier'
              AND t.tracking_code IS NULL
              AND t.deleted_at IS NULL
        ),
        'pendingDelivery', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.pickup_available_at ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Retirada Cliente'
              AND t.pickup_available = TRUE -- Ready
              -- Includes both Pickup (waiting for client) and Carrier (waiting for arrival)
              AND t.deleted_at IS NULL
        ),
        -- Outsourced
        'pendingOutsourced', (
            SELECT COALESCE(jsonb_agg(t ORDER BY t.outsourced_deadline ASC), '[]'::jsonb)
            FROM public.tickets t
            WHERE t.workspace_id = v_workspace_id
              AND t.status = 'Terceirizado'
              AND t.deleted_at IS NULL
        )
    ) INTO v_result;

    RETURN v_result;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.reset_employee_password(p_employee_id uuid, p_new_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_owner_id UUID;
BEGIN
    -- 1. Validate Admin Permissions
    -- Check if the executing user (auth.uid()) is the owner of the workspace
    -- associated with the target employee.

    SELECT w.owner_id INTO v_owner_id
    FROM public.employees e
    JOIN public.workspaces w ON e.workspace_id = w.id
    WHERE e.id = p_employee_id;

    IF v_owner_id IS NULL OR v_owner_id <> auth.uid() THEN
        RAISE EXCEPTION 'Permissão negada. Apenas o administrador da empresa pode resetar senhas.';
    END IF;

    -- 2. Update Employee
    UPDATE public.employees
    SET
        password_hash = crypt(p_new_password, gen_salt('bf')),
        must_change_password = TRUE
    WHERE id = p_employee_id;

    -- 3. Revoke all active sessions
    UPDATE public.employee_sessions
    SET revoked_at = now()
    WHERE employee_id = p_employee_id AND revoked_at IS NULL;

END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_employee(p_workspace_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_new_id UUID;
BEGIN
    INSERT INTO public.employees (workspace_id, name, username, password_hash, roles, must_change_password)
    VALUES (
        p_workspace_id,
        p_name,
        p_username,
        crypt(p_password, gen_salt('bf')),
        p_roles,
        TRUE -- Always force password change on creation
    )
    RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.update_employee(p_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    UPDATE employees
    SET
        name = p_name,
        username = p_username,
        -- Update hash only if password is provided
        password_hash = CASE
            WHEN p_password IS NOT NULL AND p_password <> ''
            THEN crypt(p_password, gen_salt('bf'))
            ELSE password_hash
        END,
        -- If password changed, maybe force change again?
        -- Usually admin changing password means reset, so yes, let's force it if password is set.
        must_change_password = CASE
            WHEN p_password IS NOT NULL AND p_password <> '' THEN TRUE
            ELSE must_change_password
        END,
        roles = p_roles
    WHERE id = p_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(p_workspace_id uuid)
 RETURNS TABLE(id uuid, workspace_id uuid, name text, username text, roles text[], created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    RETURN QUERY
    SELECT e.id, e.workspace_id, e.name, e.username, e.roles, e.created_at
    FROM public.employees e
    WHERE e.workspace_id = p_workspace_id
    AND e.deleted_at IS NULL
    ORDER BY e.created_at DESC;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.current_employee_from_token()
 RETURNS TABLE(employee_id uuid, workspace_id uuid, role text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_token_str TEXT;
    v_token UUID;
BEGIN
    -- Try to get header
    v_token_str := current_setting('request.headers', true)::json->>'x-employee-token';

    IF v_token_str IS NULL THEN
        RETURN;
    END IF;

    -- Cast to UUID
    BEGIN
        v_token := v_token_str::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN;
    END;

    RETURN QUERY
    SELECT s.employee_id, e.workspace_id, e.roles
    FROM public.employee_sessions s
    JOIN public.employees e ON e.id = s.employee_id
    WHERE s.token = v_token
      AND s.revoked_at IS NULL
      AND s.expires_at > now();
END;
$function$
;
CREATE OR REPLACE FUNCTION public.employee_change_password(p_token uuid, p_old_password text, p_new_password text)
 RETURNS TABLE(new_token uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_session RECORD;
    v_employee RECORD;
    v_new_token UUID;
BEGIN
    -- Validate Token
    SELECT * INTO v_session
    FROM public.employee_sessions
    WHERE token = p_token
      AND revoked_at IS NULL
      AND expires_at > now();

    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'Sessão inválida ou expirada.';
    END IF;

    -- Get Employee
    SELECT * INTO v_employee FROM public.employees WHERE id = v_session.employee_id;

    -- Verify Old Password
    IF v_employee.password_hash <> crypt(p_old_password, v_employee.password_hash) THEN
        RAISE EXCEPTION 'Senha atual incorreta.';
    END IF;

    -- Update Password
    UPDATE public.employees
    SET password_hash = crypt(p_new_password, gen_salt('bf')),
        must_change_password = FALSE
    WHERE id = v_session.employee_id;

    -- Revoke Old Session (Optional but recommended)
    UPDATE public.employee_sessions SET revoked_at = now() WHERE id = v_session.id;

    -- Create New Session
    INSERT INTO public.employee_sessions (employee_id, expires_at)
    VALUES (v_session.employee_id, now() + interval '30 days')
    RETURNING token INTO v_new_token;

    RETURN QUERY SELECT v_new_token;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.validate_employee_session(p_token uuid)
 RETURNS TABLE(valid boolean, employee_id uuid, workspace_id uuid, roles text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_session RECORD;
BEGIN
    SELECT s.id, s.employee_id, e.workspace_id, e.roles
    INTO v_session
    FROM public.employee_sessions s
    JOIN public.employees e ON e.id = s.employee_id
    WHERE s.token = p_token
      AND s.revoked_at IS NULL
      AND s.expires_at > now();

    IF v_session.id IS NOT NULL THEN
        -- Update Activity
        UPDATE public.employee_sessions SET last_seen_at = now() WHERE id = v_session.id;

        RETURN QUERY SELECT true, v_session.employee_id, v_session.workspace_id, v_session.roles;
    ELSE
        RETURN QUERY SELECT false, null::uuid, null::uuid, null::text[];
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.employee_logout(p_token uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    UPDATE public.employee_sessions
    SET revoked_at = now()
    WHERE token = p_token;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.employee_login(p_company_code text, p_username text, p_password text)
 RETURNS TABLE(token uuid, employee_json jsonb, must_change_password boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_workspace_id UUID;
    v_employee_record RECORD;
    v_workspace_record RECORD;
    v_token UUID;
BEGIN
    -- Find workspace
    SELECT * INTO v_workspace_record FROM public.workspaces WHERE company_code = p_company_code;
    IF v_workspace_record.id IS NULL THEN RAISE EXCEPTION 'Código da empresa inválido'; END IF;

    -- Find employee
    SELECT * INTO v_employee_record
    FROM public.employees e
    WHERE e.workspace_id = v_workspace_record.id
    AND e.username = p_username
    AND e.deleted_at IS NULL;

    IF v_employee_record.id IS NULL THEN RAISE EXCEPTION 'Usuário inválido'; END IF;

    -- Verify password
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN

        -- Create Session
        INSERT INTO public.employee_sessions (employee_id, expires_at)
        VALUES (v_employee_record.id, now() + interval '30 days')
        RETURNING public.employee_sessions.token INTO v_token;

        -- Return Data
        RETURN QUERY SELECT
            v_token,
            (to_jsonb(v_employee_record) || jsonb_build_object(
                'workspace_name', v_workspace_record.name,
                'company_code', v_workspace_record.company_code,
                'tracker_config', v_workspace_record.tracker_config
            )) as employee_json,
            v_employee_record.must_change_password;
    ELSE
        RAISE EXCEPTION 'Senha incorreta';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_owner_workspace(p_name text, p_company_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$ DECLARE v_workspace_id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'User not authenticated'; END IF; INSERT INTO public.workspaces (name, company_code, owner_id) VALUES (p_name, p_company_code, auth.uid()) RETURNING id INTO v_workspace_id; RETURN v_workspace_id; END; $function$
;
CREATE OR REPLACE FUNCTION public.create_owner_workspace_and_profile(p_name text, p_company_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$ DECLARE v_workspace_id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'User not authenticated'; END IF; INSERT INTO public.workspaces (name, company_code, owner_id) VALUES (p_name, p_company_code, auth.uid()) RETURNING id INTO v_workspace_id; INSERT INTO public.profiles (id, workspace_id, role) VALUES (auth.uid(), v_workspace_id, 'admin'); RETURN v_workspace_id; END; $function$
;

CREATE TABLE public.workspaces (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
name text NOT NULL DEFAULT NULL,
company_code text NOT NULL DEFAULT NULL,
owner_id uuid NOT NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
whatsapp_number text NULL DEFAULT NULL,
tracker_config jsonb NULL DEFAULT '{}'::jsonb
  );
CREATE UNIQUE INDEX workspaces_pkey ON public.workspaces USING btree (id);
CREATE UNIQUE INDEX workspaces_company_code_key ON public.workspaces USING btree (company_code);

CREATE POLICY "Admins can update own workspace"
      ON "public"."workspaces"
      FOR UPDATE
      TO public
      USING ((auth.uid() = owner_id))
      WITH CHECK ((auth.uid() = owner_id));
CREATE POLICY "Admin Update Workspace"
      ON "public"."workspaces"
      FOR UPDATE
      TO authenticated
      USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.workspace_id = workspaces.id) AND (profiles.role = 'admin'::text)))))
      WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.workspace_id = workspaces.id) AND (profiles.role = 'admin'::text)))));
CREATE POLICY "Admin Select Workspace"
      ON "public"."workspaces"
      FOR SELECT
      TO authenticated
      USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.workspace_id = workspaces.id)))))
      WITH CHECK (true);

CREATE TABLE public.profiles (
    id uuid NOT NULL DEFAULT NULL,
workspace_id uuid NULL DEFAULT NULL,
role text NULL DEFAULT 'admin'::text,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX profiles_pkey ON public.profiles USING btree (id);

CREATE POLICY "Users can view own profile"
      ON "public"."profiles"
      FOR SELECT
      TO public
      USING ((auth.uid() = id))
      WITH CHECK (true);
CREATE POLICY "Users can insert own profile"
      ON "public"."profiles"
      FOR INSERT
      TO public
      USING (true)
      WITH CHECK ((auth.uid() = id));

CREATE TABLE public.employees (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
username text NOT NULL DEFAULT NULL,
password_hash text NOT NULL DEFAULT NULL,
roles text[] NULL DEFAULT '{}'::text[],
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
deleted_at timestamp with time zone NULL DEFAULT NULL,
must_change_password boolean NULL DEFAULT false
  );
CREATE UNIQUE INDEX employees_pkey ON public.employees USING btree (id);
CREATE UNIQUE INDEX employees_workspace_id_username_key ON public.employees USING btree (workspace_id, username);

CREATE POLICY "Employees Access Policy"
      ON "public"."employees"
      FOR SELECT
      TO anon,authenticated
      USING ((((auth.role() = 'authenticated'::text) AND (EXISTS ( SELECT 1
   FROM workspaces w
  WHERE ((w.id = employees.workspace_id) AND (w.owner_id = auth.uid()))))) OR (workspace_id = ( SELECT current_employee_from_token.workspace_id
   FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role)))))
      WITH CHECK (true);
CREATE POLICY "Admin manage employees"
      ON "public"."employees"
      FOR ALL
      TO authenticated
      USING ((workspace_id IN ( SELECT workspaces.id
   FROM workspaces
  WHERE (workspaces.owner_id = auth.uid()))))
      WITH CHECK (true);
CREATE POLICY "Employee view colleagues"
      ON "public"."employees"
      FOR SELECT
      TO anon
      USING ((workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid))
      WITH CHECK (true);

CREATE TABLE public.device_models (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX device_models_pkey ON public.device_models USING btree (id);
CREATE UNIQUE INDEX device_models_workspace_id_name_key ON public.device_models USING btree (workspace_id, name);
CREATE INDEX idx_device_models_workspace ON public.device_models USING btree (workspace_id);
CREATE INDEX idx_device_models_name ON public.device_models USING btree (name);

CREATE POLICY "Access by Workspace Header"
      ON "public"."device_models"
      FOR ALL
      TO anon,authenticated
      USING (((workspace_id)::text = ((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text)))
      WITH CHECK (((workspace_id)::text = ((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text)));

CREATE TABLE public.internal_notes (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
ticket_id uuid NULL DEFAULT NULL,
author_id uuid NOT NULL DEFAULT NULL,
author_name text NOT NULL DEFAULT NULL,
content text NOT NULL DEFAULT NULL,
checklist_data jsonb NULL DEFAULT '[]'::jsonb,
mentions text[] NULL DEFAULT '{}'::text[],
is_resolved boolean NULL DEFAULT false,
is_archived boolean NULL DEFAULT false,
archived_at timestamp with time zone NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX internal_notes_pkey ON public.internal_notes USING btree (id);

CREATE POLICY "Acesso Total Notas"
      ON "public"."internal_notes"
      FOR ALL
      TO public
      USING (true)
      WITH CHECK (true);

CREATE TABLE public.tickets (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
client_name text NOT NULL DEFAULT NULL,
contact_info text NULL DEFAULT NULL,
os_number text NOT NULL DEFAULT NULL,
entry_date timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
deadline timestamp with time zone NULL DEFAULT NULL,
priority text NULL DEFAULT 'Normal'::text,
device_model text NOT NULL DEFAULT NULL,
serial_number text NULL DEFAULT NULL,
defect_reported text NULL DEFAULT NULL,
device_condition text NULL DEFAULT NULL,
checklist_data jsonb NULL DEFAULT '{}'::jsonb,
photos_urls text[] NULL DEFAULT '{}'::text[],
status text NULL DEFAULT 'Aberto'::text,
previous_status text NULL DEFAULT NULL,
tech_notes text NULL DEFAULT NULL,
parts_needed text NULL DEFAULT NULL,
parts_status text NULL DEFAULT 'N/A'::text,
parts_purchased_at timestamp with time zone NULL DEFAULT NULL,
parts_received_at timestamp with time zone NULL DEFAULT NULL,
budget_value numeric NULL DEFAULT NULL,
budget_status text NULL DEFAULT 'Pendente'::text,
budget_sent_at timestamp with time zone NULL DEFAULT NULL,
repair_successful boolean NULL DEFAULT NULL,
repair_start_at timestamp with time zone NULL DEFAULT NULL,
repair_end_at timestamp with time zone NULL DEFAULT NULL,
test_start_at timestamp with time zone NULL DEFAULT NULL,
pickup_available boolean NULL DEFAULT false,
pickup_available_at timestamp with time zone NULL DEFAULT NULL,
created_by uuid NULL DEFAULT NULL,
created_by_name text NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
test_notes jsonb NULL DEFAULT '[]'::jsonb,
priority_requested boolean NULL DEFAULT false,
technician_id uuid NULL DEFAULT NULL,
analysis_deadline timestamp with time zone NULL DEFAULT NULL,
checklist_final_data jsonb NULL DEFAULT '[]'::jsonb,
deleted_at timestamp with time zone NULL DEFAULT NULL,
delivered_at timestamp with time zone NULL DEFAULT NULL,
delivery_method text NULL DEFAULT NULL,
carrier_name text NULL DEFAULT NULL,
tracking_code text NULL DEFAULT NULL,
is_outsourced boolean NULL DEFAULT false,
outsourced_company_id uuid NULL DEFAULT NULL,
outsourced_deadline timestamp with time zone NULL DEFAULT NULL,
outsourced_return_count integer NULL DEFAULT 0,
outsourced_at timestamp with time zone NULL DEFAULT NULL,
outsourced_failure_reason text NULL DEFAULT NULL,
outsourced_notes jsonb NULL DEFAULT '[]'::jsonb
  );
CREATE UNIQUE INDEX tickets_pkey ON public.tickets USING btree (id);
CREATE INDEX idx_tickets_workspace_status ON public.tickets USING btree (workspace_id, status);
CREATE INDEX idx_tickets_technician ON public.tickets USING btree (technician_id);
CREATE INDEX idx_tickets_deleted_at ON public.tickets USING btree (deleted_at);
CREATE INDEX idx_tickets_workspace_created ON public.tickets USING btree (workspace_id, created_at DESC);
CREATE INDEX idx_tickets_workspace_tech_created ON public.tickets USING btree (workspace_id, technician_id, created_at DESC);
CREATE INDEX idx_tickets_active_kanban ON public.tickets USING btree (workspace_id, status, created_at DESC) WHERE ((delivered_at IS NULL) AND (deleted_at IS NULL));
CREATE INDEX idx_tickets_outsourced_company_id ON public.tickets USING btree (outsourced_company_id);

CREATE POLICY "Admin All Access"
      ON "public"."tickets"
      FOR ALL
      TO authenticated
      USING ((workspace_id IN ( SELECT workspaces.id
   FROM workspaces
  WHERE (workspaces.owner_id = auth.uid()))))
      WITH CHECK ((workspace_id IN ( SELECT workspaces.id
   FROM workspaces
  WHERE (workspaces.owner_id = auth.uid()))));
CREATE POLICY "Employee Access via Header"
      ON "public"."tickets"
      FOR ALL
      TO anon
      USING ((workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid))
      WITH CHECK ((workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid));
CREATE POLICY "Tickets Access Policy"
      ON "public"."tickets"
      FOR ALL
      TO anon,authenticated
      USING ((((auth.role() = 'authenticated'::text) AND (EXISTS ( SELECT 1
   FROM workspaces w
  WHERE ((w.id = tickets.workspace_id) AND (w.owner_id = auth.uid()))))) OR (workspace_id = ( SELECT current_employee_from_token.workspace_id
   FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role)))))
      WITH CHECK (true);

CREATE TRIGGER on_ticket_change AFTER INSERT OR UPDATE ON public.tickets FOR EACH ROW EXECUTE FUNCTION log_ticket_changes();

CREATE TABLE public.checklist_templates (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
items jsonb NOT NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
type text NULL DEFAULT 'entry'::text
  );
CREATE UNIQUE INDEX checklist_templates_pkey ON public.checklist_templates USING btree (id);

CREATE POLICY "Admin manage templates"
      ON "public"."checklist_templates"
      FOR ALL
      TO authenticated
      USING ((workspace_id IN ( SELECT workspaces.id
   FROM workspaces
  WHERE (workspaces.owner_id = auth.uid()))))
      WITH CHECK (true);
CREATE POLICY "Employee use templates"
      ON "public"."checklist_templates"
      FOR ALL
      TO anon
      USING ((workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid))
      WITH CHECK (true);

CREATE TABLE public.employee_sessions (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
employee_id uuid NOT NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
expires_at timestamp with time zone NOT NULL DEFAULT NULL,
revoked_at timestamp with time zone NULL DEFAULT NULL,
last_seen_at timestamp with time zone NULL DEFAULT timezone('utc'::text, now()),
token uuid NOT NULL DEFAULT gen_random_uuid()
  );
CREATE UNIQUE INDEX employee_sessions_pkey ON public.employee_sessions USING btree (id);
CREATE INDEX idx_employee_sessions_employee_id ON public.employee_sessions USING btree (employee_id);
CREATE INDEX idx_employee_sessions_token ON public.employee_sessions USING btree (token);

CREATE TABLE public.ticket_logs (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
ticket_id uuid NULL DEFAULT NULL,
action text NOT NULL DEFAULT NULL,
details text NULL DEFAULT NULL,
user_name text NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX ticket_logs_pkey ON public.ticket_logs USING btree (id);

CREATE POLICY "Allow All for Authenticated"
      ON "public"."ticket_logs"
      FOR ALL
      TO authenticated
      USING (true)
      WITH CHECK (true);
CREATE POLICY "Admin view logs"
      ON "public"."ticket_logs"
      FOR ALL
      TO authenticated
      USING ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE ((t.id = ticket_logs.ticket_id) AND (t.workspace_id IN ( SELECT workspaces.id
           FROM workspaces
          WHERE (workspaces.owner_id = auth.uid())))))))
      WITH CHECK (true);
CREATE POLICY "Employee view/create logs"
      ON "public"."ticket_logs"
      FOR ALL
      TO anon
      USING ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE ((t.id = ticket_logs.ticket_id) AND (t.workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid)))))
      WITH CHECK (true);

CREATE TABLE public.suppliers (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
phone text NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
deleted_at timestamp with time zone NULL DEFAULT NULL
  );
CREATE UNIQUE INDEX suppliers_pkey ON public.suppliers USING btree (id);

CREATE POLICY "Enable all access for users in same workspace"
      ON "public"."suppliers"
      FOR ALL
      TO public
      USING ((workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid))
      WITH CHECK (true);

CREATE TABLE public.outsourced_companies (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
phone text NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX outsourced_companies_pkey ON public.outsourced_companies USING btree (id);

CREATE POLICY "Employee Access Standard"
      ON "public"."outsourced_companies"
      FOR ALL
      TO public
      USING ((workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid))
      WITH CHECK ((workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid));
CREATE POLICY "Allow All Authenticated"
      ON "public"."outsourced_companies"
      FOR ALL
      TO authenticated
      USING (true)
      WITH CHECK (true);

CREATE TABLE public.notifications (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
ticket_id uuid NULL DEFAULT NULL,
recipient_role text NULL DEFAULT NULL,
recipient_user_id uuid NULL DEFAULT NULL,
type text NOT NULL DEFAULT 'info'::text,
message text NOT NULL DEFAULT NULL,
is_read boolean NULL DEFAULT false,
is_pinned boolean NULL DEFAULT false,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX notifications_pkey ON public.notifications USING btree (id);

CREATE POLICY "Admin manage notifications"
      ON "public"."notifications"
      FOR ALL
      TO authenticated
      USING ((EXISTS ( SELECT 1
   FROM (tickets t
     JOIN workspaces w ON ((t.workspace_id = w.id)))
  WHERE ((t.id = notifications.ticket_id) AND (w.owner_id = auth.uid())))))
      WITH CHECK (true);
CREATE POLICY "Access notifications via ticket workspace"
      ON "public"."notifications"
      FOR ALL
      TO anon
      USING ((EXISTS ( SELECT 1
   FROM tickets t
  WHERE ((t.id = notifications.ticket_id) AND (t.workspace_id = (((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text))::uuid)))))
      WITH CHECK (true);

CREATE TABLE public.terceirizados (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
phone text NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX terceirizados_pkey ON public.terceirizados USING btree (id);

CREATE POLICY "Acesso Total Terceirizados"
      ON "public"."terceirizados"
      FOR ALL
      TO authenticated
      USING (true)
      WITH CHECK (true);

CREATE TABLE public.defects (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX defects_pkey ON public.defects USING btree (id);
CREATE UNIQUE INDEX defects_workspace_id_name_key ON public.defects USING btree (workspace_id, name);
CREATE INDEX idx_defects_workspace ON public.defects USING btree (workspace_id);
CREATE INDEX idx_defects_name ON public.defects USING btree (name);

CREATE POLICY "Access by Workspace Header"
      ON "public"."defects"
      FOR ALL
      TO anon,authenticated
      USING (((workspace_id)::text = ((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text)))
      WITH CHECK (((workspace_id)::text = ((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text)));

CREATE TABLE public.defect_options (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
workspace_id uuid NOT NULL DEFAULT NULL,
name text NOT NULL DEFAULT NULL,
created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
  );
CREATE UNIQUE INDEX defect_options_pkey ON public.defect_options USING btree (id);
CREATE UNIQUE INDEX defect_options_workspace_id_name_key ON public.defect_options USING btree (workspace_id, name);
CREATE INDEX idx_defect_options_workspace ON public.defect_options USING btree (workspace_id);
CREATE INDEX idx_defect_options_name ON public.defect_options USING btree (name);

CREATE POLICY "Access by Workspace Header"
      ON "public"."defect_options"
      FOR ALL
      TO anon,authenticated
      USING (((workspace_id)::text = ((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text)))
      WITH CHECK (((workspace_id)::text = ((current_setting('request.headers'::text, true))::json ->> 'x-workspace-id'::text)));

GRANT INSERT ON TABLE public.workspaces TO postgres;
GRANT SELECT ON TABLE public.workspaces TO postgres;
GRANT UPDATE ON TABLE public.workspaces TO postgres;
GRANT DELETE ON TABLE public.workspaces TO postgres;
GRANT TRUNCATE ON TABLE public.workspaces TO postgres;
GRANT REFERENCES ON TABLE public.workspaces TO postgres;
GRANT TRIGGER ON TABLE public.workspaces TO postgres;
GRANT INSERT ON TABLE public.workspaces TO anon;
GRANT SELECT ON TABLE public.workspaces TO anon;
GRANT UPDATE ON TABLE public.workspaces TO anon;
GRANT DELETE ON TABLE public.workspaces TO anon;
GRANT TRUNCATE ON TABLE public.workspaces TO anon;
GRANT REFERENCES ON TABLE public.workspaces TO anon;
GRANT TRIGGER ON TABLE public.workspaces TO anon;
GRANT INSERT ON TABLE public.workspaces TO authenticated;
GRANT SELECT ON TABLE public.workspaces TO authenticated;
GRANT UPDATE ON TABLE public.workspaces TO authenticated;
GRANT DELETE ON TABLE public.workspaces TO authenticated;
GRANT TRUNCATE ON TABLE public.workspaces TO authenticated;
GRANT REFERENCES ON TABLE public.workspaces TO authenticated;
GRANT TRIGGER ON TABLE public.workspaces TO authenticated;
GRANT INSERT ON TABLE public.workspaces TO service_role;
GRANT SELECT ON TABLE public.workspaces TO service_role;
GRANT UPDATE ON TABLE public.workspaces TO service_role;
GRANT DELETE ON TABLE public.workspaces TO service_role;
GRANT TRUNCATE ON TABLE public.workspaces TO service_role;
GRANT REFERENCES ON TABLE public.workspaces TO service_role;
GRANT TRIGGER ON TABLE public.workspaces TO service_role;
GRANT INSERT ON TABLE public.profiles TO postgres;
GRANT SELECT ON TABLE public.profiles TO postgres;
GRANT UPDATE ON TABLE public.profiles TO postgres;
GRANT DELETE ON TABLE public.profiles TO postgres;
GRANT TRUNCATE ON TABLE public.profiles TO postgres;
GRANT REFERENCES ON TABLE public.profiles TO postgres;
GRANT TRIGGER ON TABLE public.profiles TO postgres;
GRANT INSERT ON TABLE public.profiles TO anon;
GRANT SELECT ON TABLE public.profiles TO anon;
GRANT UPDATE ON TABLE public.profiles TO anon;
GRANT DELETE ON TABLE public.profiles TO anon;
GRANT TRUNCATE ON TABLE public.profiles TO anon;
GRANT REFERENCES ON TABLE public.profiles TO anon;
GRANT TRIGGER ON TABLE public.profiles TO anon;
GRANT INSERT ON TABLE public.profiles TO authenticated;
GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE ON TABLE public.profiles TO authenticated;
GRANT DELETE ON TABLE public.profiles TO authenticated;
GRANT TRUNCATE ON TABLE public.profiles TO authenticated;
GRANT REFERENCES ON TABLE public.profiles TO authenticated;
GRANT TRIGGER ON TABLE public.profiles TO authenticated;
GRANT INSERT ON TABLE public.profiles TO service_role;
GRANT SELECT ON TABLE public.profiles TO service_role;
GRANT UPDATE ON TABLE public.profiles TO service_role;
GRANT DELETE ON TABLE public.profiles TO service_role;
GRANT TRUNCATE ON TABLE public.profiles TO service_role;
GRANT REFERENCES ON TABLE public.profiles TO service_role;
GRANT TRIGGER ON TABLE public.profiles TO service_role;
GRANT INSERT ON TABLE public.employees TO postgres;
GRANT SELECT ON TABLE public.employees TO postgres;
GRANT UPDATE ON TABLE public.employees TO postgres;
GRANT DELETE ON TABLE public.employees TO postgres;
GRANT TRUNCATE ON TABLE public.employees TO postgres;
GRANT REFERENCES ON TABLE public.employees TO postgres;
GRANT TRIGGER ON TABLE public.employees TO postgres;
GRANT INSERT ON TABLE public.employees TO anon;
GRANT SELECT ON TABLE public.employees TO anon;
GRANT UPDATE ON TABLE public.employees TO anon;
GRANT DELETE ON TABLE public.employees TO anon;
GRANT TRUNCATE ON TABLE public.employees TO anon;
GRANT REFERENCES ON TABLE public.employees TO anon;
GRANT TRIGGER ON TABLE public.employees TO anon;
GRANT INSERT ON TABLE public.employees TO authenticated;
GRANT SELECT ON TABLE public.employees TO authenticated;
GRANT UPDATE ON TABLE public.employees TO authenticated;
GRANT DELETE ON TABLE public.employees TO authenticated;
GRANT TRUNCATE ON TABLE public.employees TO authenticated;
GRANT REFERENCES ON TABLE public.employees TO authenticated;
GRANT TRIGGER ON TABLE public.employees TO authenticated;
GRANT INSERT ON TABLE public.employees TO service_role;
GRANT SELECT ON TABLE public.employees TO service_role;
GRANT UPDATE ON TABLE public.employees TO service_role;
GRANT DELETE ON TABLE public.employees TO service_role;
GRANT TRUNCATE ON TABLE public.employees TO service_role;
GRANT REFERENCES ON TABLE public.employees TO service_role;
GRANT TRIGGER ON TABLE public.employees TO service_role;
GRANT INSERT ON TABLE public.device_models TO postgres;
GRANT SELECT ON TABLE public.device_models TO postgres;
GRANT UPDATE ON TABLE public.device_models TO postgres;
GRANT DELETE ON TABLE public.device_models TO postgres;
GRANT TRUNCATE ON TABLE public.device_models TO postgres;
GRANT REFERENCES ON TABLE public.device_models TO postgres;
GRANT TRIGGER ON TABLE public.device_models TO postgres;
GRANT INSERT ON TABLE public.device_models TO anon;
GRANT SELECT ON TABLE public.device_models TO anon;
GRANT UPDATE ON TABLE public.device_models TO anon;
GRANT DELETE ON TABLE public.device_models TO anon;
GRANT TRUNCATE ON TABLE public.device_models TO anon;
GRANT REFERENCES ON TABLE public.device_models TO anon;
GRANT TRIGGER ON TABLE public.device_models TO anon;
GRANT INSERT ON TABLE public.device_models TO authenticated;
GRANT SELECT ON TABLE public.device_models TO authenticated;
GRANT UPDATE ON TABLE public.device_models TO authenticated;
GRANT DELETE ON TABLE public.device_models TO authenticated;
GRANT TRUNCATE ON TABLE public.device_models TO authenticated;
GRANT REFERENCES ON TABLE public.device_models TO authenticated;
GRANT TRIGGER ON TABLE public.device_models TO authenticated;
GRANT INSERT ON TABLE public.device_models TO service_role;
GRANT SELECT ON TABLE public.device_models TO service_role;
GRANT UPDATE ON TABLE public.device_models TO service_role;
GRANT DELETE ON TABLE public.device_models TO service_role;
GRANT TRUNCATE ON TABLE public.device_models TO service_role;
GRANT REFERENCES ON TABLE public.device_models TO service_role;
GRANT TRIGGER ON TABLE public.device_models TO service_role;
GRANT INSERT ON TABLE public.internal_notes TO postgres;
GRANT SELECT ON TABLE public.internal_notes TO postgres;
GRANT UPDATE ON TABLE public.internal_notes TO postgres;
GRANT DELETE ON TABLE public.internal_notes TO postgres;
GRANT TRUNCATE ON TABLE public.internal_notes TO postgres;
GRANT REFERENCES ON TABLE public.internal_notes TO postgres;
GRANT TRIGGER ON TABLE public.internal_notes TO postgres;
GRANT INSERT ON TABLE public.internal_notes TO anon;
GRANT SELECT ON TABLE public.internal_notes TO anon;
GRANT UPDATE ON TABLE public.internal_notes TO anon;
GRANT DELETE ON TABLE public.internal_notes TO anon;
GRANT TRUNCATE ON TABLE public.internal_notes TO anon;
GRANT REFERENCES ON TABLE public.internal_notes TO anon;
GRANT TRIGGER ON TABLE public.internal_notes TO anon;
GRANT INSERT ON TABLE public.internal_notes TO authenticated;
GRANT SELECT ON TABLE public.internal_notes TO authenticated;
GRANT UPDATE ON TABLE public.internal_notes TO authenticated;
GRANT DELETE ON TABLE public.internal_notes TO authenticated;
GRANT TRUNCATE ON TABLE public.internal_notes TO authenticated;
GRANT REFERENCES ON TABLE public.internal_notes TO authenticated;
GRANT TRIGGER ON TABLE public.internal_notes TO authenticated;
GRANT INSERT ON TABLE public.internal_notes TO service_role;
GRANT SELECT ON TABLE public.internal_notes TO service_role;
GRANT UPDATE ON TABLE public.internal_notes TO service_role;
GRANT DELETE ON TABLE public.internal_notes TO service_role;
GRANT TRUNCATE ON TABLE public.internal_notes TO service_role;
GRANT REFERENCES ON TABLE public.internal_notes TO service_role;
GRANT TRIGGER ON TABLE public.internal_notes TO service_role;
GRANT INSERT ON TABLE public.tickets TO postgres;
GRANT SELECT ON TABLE public.tickets TO postgres;
GRANT UPDATE ON TABLE public.tickets TO postgres;
GRANT DELETE ON TABLE public.tickets TO postgres;
GRANT TRUNCATE ON TABLE public.tickets TO postgres;
GRANT REFERENCES ON TABLE public.tickets TO postgres;
GRANT TRIGGER ON TABLE public.tickets TO postgres;
GRANT INSERT ON TABLE public.tickets TO anon;
GRANT SELECT ON TABLE public.tickets TO anon;
GRANT UPDATE ON TABLE public.tickets TO anon;
GRANT DELETE ON TABLE public.tickets TO anon;
GRANT TRUNCATE ON TABLE public.tickets TO anon;
GRANT REFERENCES ON TABLE public.tickets TO anon;
GRANT TRIGGER ON TABLE public.tickets TO anon;
GRANT INSERT ON TABLE public.tickets TO authenticated;
GRANT SELECT ON TABLE public.tickets TO authenticated;
GRANT UPDATE ON TABLE public.tickets TO authenticated;
GRANT DELETE ON TABLE public.tickets TO authenticated;
GRANT TRUNCATE ON TABLE public.tickets TO authenticated;
GRANT REFERENCES ON TABLE public.tickets TO authenticated;
GRANT TRIGGER ON TABLE public.tickets TO authenticated;
GRANT INSERT ON TABLE public.tickets TO service_role;
GRANT SELECT ON TABLE public.tickets TO service_role;
GRANT UPDATE ON TABLE public.tickets TO service_role;
GRANT DELETE ON TABLE public.tickets TO service_role;
GRANT TRUNCATE ON TABLE public.tickets TO service_role;
GRANT REFERENCES ON TABLE public.tickets TO service_role;
GRANT TRIGGER ON TABLE public.tickets TO service_role;
GRANT INSERT ON TABLE public.checklist_templates TO postgres;
GRANT SELECT ON TABLE public.checklist_templates TO postgres;
GRANT UPDATE ON TABLE public.checklist_templates TO postgres;
GRANT DELETE ON TABLE public.checklist_templates TO postgres;
GRANT TRUNCATE ON TABLE public.checklist_templates TO postgres;
GRANT REFERENCES ON TABLE public.checklist_templates TO postgres;
GRANT TRIGGER ON TABLE public.checklist_templates TO postgres;
GRANT INSERT ON TABLE public.checklist_templates TO anon;
GRANT SELECT ON TABLE public.checklist_templates TO anon;
GRANT UPDATE ON TABLE public.checklist_templates TO anon;
GRANT DELETE ON TABLE public.checklist_templates TO anon;
GRANT TRUNCATE ON TABLE public.checklist_templates TO anon;
GRANT REFERENCES ON TABLE public.checklist_templates TO anon;
GRANT TRIGGER ON TABLE public.checklist_templates TO anon;
GRANT INSERT ON TABLE public.checklist_templates TO authenticated;
GRANT SELECT ON TABLE public.checklist_templates TO authenticated;
GRANT UPDATE ON TABLE public.checklist_templates TO authenticated;
GRANT DELETE ON TABLE public.checklist_templates TO authenticated;
GRANT TRUNCATE ON TABLE public.checklist_templates TO authenticated;
GRANT REFERENCES ON TABLE public.checklist_templates TO authenticated;
GRANT TRIGGER ON TABLE public.checklist_templates TO authenticated;
GRANT INSERT ON TABLE public.checklist_templates TO service_role;
GRANT SELECT ON TABLE public.checklist_templates TO service_role;
GRANT UPDATE ON TABLE public.checklist_templates TO service_role;
GRANT DELETE ON TABLE public.checklist_templates TO service_role;
GRANT TRUNCATE ON TABLE public.checklist_templates TO service_role;
GRANT REFERENCES ON TABLE public.checklist_templates TO service_role;
GRANT TRIGGER ON TABLE public.checklist_templates TO service_role;
GRANT INSERT ON TABLE public.employee_sessions TO postgres;
GRANT SELECT ON TABLE public.employee_sessions TO postgres;
GRANT UPDATE ON TABLE public.employee_sessions TO postgres;
GRANT DELETE ON TABLE public.employee_sessions TO postgres;
GRANT TRUNCATE ON TABLE public.employee_sessions TO postgres;
GRANT REFERENCES ON TABLE public.employee_sessions TO postgres;
GRANT TRIGGER ON TABLE public.employee_sessions TO postgres;
GRANT INSERT ON TABLE public.employee_sessions TO anon;
GRANT SELECT ON TABLE public.employee_sessions TO anon;
GRANT UPDATE ON TABLE public.employee_sessions TO anon;
GRANT DELETE ON TABLE public.employee_sessions TO anon;
GRANT TRUNCATE ON TABLE public.employee_sessions TO anon;
GRANT REFERENCES ON TABLE public.employee_sessions TO anon;
GRANT TRIGGER ON TABLE public.employee_sessions TO anon;
GRANT INSERT ON TABLE public.employee_sessions TO authenticated;
GRANT SELECT ON TABLE public.employee_sessions TO authenticated;
GRANT UPDATE ON TABLE public.employee_sessions TO authenticated;
GRANT DELETE ON TABLE public.employee_sessions TO authenticated;
GRANT TRUNCATE ON TABLE public.employee_sessions TO authenticated;
GRANT REFERENCES ON TABLE public.employee_sessions TO authenticated;
GRANT TRIGGER ON TABLE public.employee_sessions TO authenticated;
GRANT INSERT ON TABLE public.employee_sessions TO service_role;
GRANT SELECT ON TABLE public.employee_sessions TO service_role;
GRANT UPDATE ON TABLE public.employee_sessions TO service_role;
GRANT DELETE ON TABLE public.employee_sessions TO service_role;
GRANT TRUNCATE ON TABLE public.employee_sessions TO service_role;
GRANT REFERENCES ON TABLE public.employee_sessions TO service_role;
GRANT TRIGGER ON TABLE public.employee_sessions TO service_role;
GRANT INSERT ON TABLE public.ticket_logs TO postgres;
GRANT SELECT ON TABLE public.ticket_logs TO postgres;
GRANT UPDATE ON TABLE public.ticket_logs TO postgres;
GRANT DELETE ON TABLE public.ticket_logs TO postgres;
GRANT TRUNCATE ON TABLE public.ticket_logs TO postgres;
GRANT REFERENCES ON TABLE public.ticket_logs TO postgres;
GRANT TRIGGER ON TABLE public.ticket_logs TO postgres;
GRANT INSERT ON TABLE public.ticket_logs TO anon;
GRANT SELECT ON TABLE public.ticket_logs TO anon;
GRANT UPDATE ON TABLE public.ticket_logs TO anon;
GRANT DELETE ON TABLE public.ticket_logs TO anon;
GRANT TRUNCATE ON TABLE public.ticket_logs TO anon;
GRANT REFERENCES ON TABLE public.ticket_logs TO anon;
GRANT TRIGGER ON TABLE public.ticket_logs TO anon;
GRANT INSERT ON TABLE public.ticket_logs TO authenticated;
GRANT SELECT ON TABLE public.ticket_logs TO authenticated;
GRANT UPDATE ON TABLE public.ticket_logs TO authenticated;
GRANT DELETE ON TABLE public.ticket_logs TO authenticated;
GRANT TRUNCATE ON TABLE public.ticket_logs TO authenticated;
GRANT REFERENCES ON TABLE public.ticket_logs TO authenticated;
GRANT TRIGGER ON TABLE public.ticket_logs TO authenticated;
GRANT INSERT ON TABLE public.ticket_logs TO service_role;
GRANT SELECT ON TABLE public.ticket_logs TO service_role;
GRANT UPDATE ON TABLE public.ticket_logs TO service_role;
GRANT DELETE ON TABLE public.ticket_logs TO service_role;
GRANT TRUNCATE ON TABLE public.ticket_logs TO service_role;
GRANT REFERENCES ON TABLE public.ticket_logs TO service_role;
GRANT TRIGGER ON TABLE public.ticket_logs TO service_role;
GRANT INSERT ON TABLE public.suppliers TO postgres;
GRANT SELECT ON TABLE public.suppliers TO postgres;
GRANT UPDATE ON TABLE public.suppliers TO postgres;
GRANT DELETE ON TABLE public.suppliers TO postgres;
GRANT TRUNCATE ON TABLE public.suppliers TO postgres;
GRANT REFERENCES ON TABLE public.suppliers TO postgres;
GRANT TRIGGER ON TABLE public.suppliers TO postgres;
GRANT INSERT ON TABLE public.suppliers TO anon;
GRANT SELECT ON TABLE public.suppliers TO anon;
GRANT UPDATE ON TABLE public.suppliers TO anon;
GRANT DELETE ON TABLE public.suppliers TO anon;
GRANT TRUNCATE ON TABLE public.suppliers TO anon;
GRANT REFERENCES ON TABLE public.suppliers TO anon;
GRANT TRIGGER ON TABLE public.suppliers TO anon;
GRANT INSERT ON TABLE public.suppliers TO authenticated;
GRANT SELECT ON TABLE public.suppliers TO authenticated;
GRANT UPDATE ON TABLE public.suppliers TO authenticated;
GRANT DELETE ON TABLE public.suppliers TO authenticated;
GRANT TRUNCATE ON TABLE public.suppliers TO authenticated;
GRANT REFERENCES ON TABLE public.suppliers TO authenticated;
GRANT TRIGGER ON TABLE public.suppliers TO authenticated;
GRANT INSERT ON TABLE public.suppliers TO service_role;
GRANT SELECT ON TABLE public.suppliers TO service_role;
GRANT UPDATE ON TABLE public.suppliers TO service_role;
GRANT DELETE ON TABLE public.suppliers TO service_role;
GRANT TRUNCATE ON TABLE public.suppliers TO service_role;
GRANT REFERENCES ON TABLE public.suppliers TO service_role;
GRANT TRIGGER ON TABLE public.suppliers TO service_role;
GRANT INSERT ON TABLE public.outsourced_companies TO postgres;
GRANT SELECT ON TABLE public.outsourced_companies TO postgres;
GRANT UPDATE ON TABLE public.outsourced_companies TO postgres;
GRANT DELETE ON TABLE public.outsourced_companies TO postgres;
GRANT TRUNCATE ON TABLE public.outsourced_companies TO postgres;
GRANT REFERENCES ON TABLE public.outsourced_companies TO postgres;
GRANT TRIGGER ON TABLE public.outsourced_companies TO postgres;
GRANT INSERT ON TABLE public.outsourced_companies TO anon;
GRANT SELECT ON TABLE public.outsourced_companies TO anon;
GRANT UPDATE ON TABLE public.outsourced_companies TO anon;
GRANT DELETE ON TABLE public.outsourced_companies TO anon;
GRANT TRUNCATE ON TABLE public.outsourced_companies TO anon;
GRANT REFERENCES ON TABLE public.outsourced_companies TO anon;
GRANT TRIGGER ON TABLE public.outsourced_companies TO anon;
GRANT INSERT ON TABLE public.outsourced_companies TO authenticated;
GRANT SELECT ON TABLE public.outsourced_companies TO authenticated;
GRANT UPDATE ON TABLE public.outsourced_companies TO authenticated;
GRANT DELETE ON TABLE public.outsourced_companies TO authenticated;
GRANT TRUNCATE ON TABLE public.outsourced_companies TO authenticated;
GRANT REFERENCES ON TABLE public.outsourced_companies TO authenticated;
GRANT TRIGGER ON TABLE public.outsourced_companies TO authenticated;
GRANT INSERT ON TABLE public.outsourced_companies TO service_role;
GRANT SELECT ON TABLE public.outsourced_companies TO service_role;
GRANT UPDATE ON TABLE public.outsourced_companies TO service_role;
GRANT DELETE ON TABLE public.outsourced_companies TO service_role;
GRANT TRUNCATE ON TABLE public.outsourced_companies TO service_role;
GRANT REFERENCES ON TABLE public.outsourced_companies TO service_role;
GRANT TRIGGER ON TABLE public.outsourced_companies TO service_role;
GRANT INSERT ON TABLE public.notifications TO postgres;
GRANT SELECT ON TABLE public.notifications TO postgres;
GRANT UPDATE ON TABLE public.notifications TO postgres;
GRANT DELETE ON TABLE public.notifications TO postgres;
GRANT TRUNCATE ON TABLE public.notifications TO postgres;
GRANT REFERENCES ON TABLE public.notifications TO postgres;
GRANT TRIGGER ON TABLE public.notifications TO postgres;
GRANT INSERT ON TABLE public.notifications TO anon;
GRANT SELECT ON TABLE public.notifications TO anon;
GRANT UPDATE ON TABLE public.notifications TO anon;
GRANT DELETE ON TABLE public.notifications TO anon;
GRANT TRUNCATE ON TABLE public.notifications TO anon;
GRANT REFERENCES ON TABLE public.notifications TO anon;
GRANT TRIGGER ON TABLE public.notifications TO anon;
GRANT INSERT ON TABLE public.notifications TO authenticated;
GRANT SELECT ON TABLE public.notifications TO authenticated;
GRANT UPDATE ON TABLE public.notifications TO authenticated;
GRANT DELETE ON TABLE public.notifications TO authenticated;
GRANT TRUNCATE ON TABLE public.notifications TO authenticated;
GRANT REFERENCES ON TABLE public.notifications TO authenticated;
GRANT TRIGGER ON TABLE public.notifications TO authenticated;
GRANT INSERT ON TABLE public.notifications TO service_role;
GRANT SELECT ON TABLE public.notifications TO service_role;
GRANT UPDATE ON TABLE public.notifications TO service_role;
GRANT DELETE ON TABLE public.notifications TO service_role;
GRANT TRUNCATE ON TABLE public.notifications TO service_role;
GRANT REFERENCES ON TABLE public.notifications TO service_role;
GRANT TRIGGER ON TABLE public.notifications TO service_role;
GRANT INSERT ON TABLE public.terceirizados TO postgres;
GRANT SELECT ON TABLE public.terceirizados TO postgres;
GRANT UPDATE ON TABLE public.terceirizados TO postgres;
GRANT DELETE ON TABLE public.terceirizados TO postgres;
GRANT TRUNCATE ON TABLE public.terceirizados TO postgres;
GRANT REFERENCES ON TABLE public.terceirizados TO postgres;
GRANT TRIGGER ON TABLE public.terceirizados TO postgres;
GRANT INSERT ON TABLE public.terceirizados TO anon;
GRANT SELECT ON TABLE public.terceirizados TO anon;
GRANT UPDATE ON TABLE public.terceirizados TO anon;
GRANT DELETE ON TABLE public.terceirizados TO anon;
GRANT TRUNCATE ON TABLE public.terceirizados TO anon;
GRANT REFERENCES ON TABLE public.terceirizados TO anon;
GRANT TRIGGER ON TABLE public.terceirizados TO anon;
GRANT INSERT ON TABLE public.terceirizados TO authenticated;
GRANT SELECT ON TABLE public.terceirizados TO authenticated;
GRANT UPDATE ON TABLE public.terceirizados TO authenticated;
GRANT DELETE ON TABLE public.terceirizados TO authenticated;
GRANT TRUNCATE ON TABLE public.terceirizados TO authenticated;
GRANT REFERENCES ON TABLE public.terceirizados TO authenticated;
GRANT TRIGGER ON TABLE public.terceirizados TO authenticated;
GRANT INSERT ON TABLE public.terceirizados TO service_role;
GRANT SELECT ON TABLE public.terceirizados TO service_role;
GRANT UPDATE ON TABLE public.terceirizados TO service_role;
GRANT DELETE ON TABLE public.terceirizados TO service_role;
GRANT TRUNCATE ON TABLE public.terceirizados TO service_role;
GRANT REFERENCES ON TABLE public.terceirizados TO service_role;
GRANT TRIGGER ON TABLE public.terceirizados TO service_role;
GRANT INSERT ON TABLE public.defects TO postgres;
GRANT SELECT ON TABLE public.defects TO postgres;
GRANT UPDATE ON TABLE public.defects TO postgres;
GRANT DELETE ON TABLE public.defects TO postgres;
GRANT TRUNCATE ON TABLE public.defects TO postgres;
GRANT REFERENCES ON TABLE public.defects TO postgres;
GRANT TRIGGER ON TABLE public.defects TO postgres;
GRANT INSERT ON TABLE public.defects TO anon;
GRANT SELECT ON TABLE public.defects TO anon;
GRANT UPDATE ON TABLE public.defects TO anon;
GRANT DELETE ON TABLE public.defects TO anon;
GRANT TRUNCATE ON TABLE public.defects TO anon;
GRANT REFERENCES ON TABLE public.defects TO anon;
GRANT TRIGGER ON TABLE public.defects TO anon;
GRANT INSERT ON TABLE public.defects TO authenticated;
GRANT SELECT ON TABLE public.defects TO authenticated;
GRANT UPDATE ON TABLE public.defects TO authenticated;
GRANT DELETE ON TABLE public.defects TO authenticated;
GRANT TRUNCATE ON TABLE public.defects TO authenticated;
GRANT REFERENCES ON TABLE public.defects TO authenticated;
GRANT TRIGGER ON TABLE public.defects TO authenticated;
GRANT INSERT ON TABLE public.defects TO service_role;
GRANT SELECT ON TABLE public.defects TO service_role;
GRANT UPDATE ON TABLE public.defects TO service_role;
GRANT DELETE ON TABLE public.defects TO service_role;
GRANT TRUNCATE ON TABLE public.defects TO service_role;
GRANT REFERENCES ON TABLE public.defects TO service_role;
GRANT TRIGGER ON TABLE public.defects TO service_role;
GRANT INSERT ON TABLE public.defect_options TO postgres;
GRANT SELECT ON TABLE public.defect_options TO postgres;
GRANT UPDATE ON TABLE public.defect_options TO postgres;
GRANT DELETE ON TABLE public.defect_options TO postgres;
GRANT TRUNCATE ON TABLE public.defect_options TO postgres;
GRANT REFERENCES ON TABLE public.defect_options TO postgres;
GRANT TRIGGER ON TABLE public.defect_options TO postgres;
GRANT INSERT ON TABLE public.defect_options TO anon;
GRANT SELECT ON TABLE public.defect_options TO anon;
GRANT UPDATE ON TABLE public.defect_options TO anon;
GRANT DELETE ON TABLE public.defect_options TO anon;
GRANT TRUNCATE ON TABLE public.defect_options TO anon;
GRANT REFERENCES ON TABLE public.defect_options TO anon;
GRANT TRIGGER ON TABLE public.defect_options TO anon;
GRANT INSERT ON TABLE public.defect_options TO authenticated;
GRANT SELECT ON TABLE public.defect_options TO authenticated;
GRANT UPDATE ON TABLE public.defect_options TO authenticated;
GRANT DELETE ON TABLE public.defect_options TO authenticated;
GRANT TRUNCATE ON TABLE public.defect_options TO authenticated;
GRANT REFERENCES ON TABLE public.defect_options TO authenticated;
GRANT TRIGGER ON TABLE public.defect_options TO authenticated;
GRANT INSERT ON TABLE public.defect_options TO service_role;
GRANT SELECT ON TABLE public.defect_options TO service_role;
GRANT UPDATE ON TABLE public.defect_options TO service_role;
GRANT DELETE ON TABLE public.defect_options TO service_role;
GRANT TRUNCATE ON TABLE public.defect_options TO service_role;
GRANT REFERENCES ON TABLE public.defect_options TO service_role;
GRANT TRIGGER ON TABLE public.defect_options TO service_role;
