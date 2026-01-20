-- Migration: Dashboard KPIs RPC and Indexes
-- Description: Adds indexes for performance and an RPC to calculate dashboard metrics server-side.

-- 1. Ensure Soft Delete Column Exists (Safe Operation)
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- 2. Performance Indexes
-- Base index for filtering by workspace and date (most common filter)
CREATE INDEX IF NOT EXISTS idx_tickets_workspace_created ON public.tickets (workspace_id, created_at DESC);

-- Index for Technician Filter
CREATE INDEX IF NOT EXISTS idx_tickets_workspace_tech_created ON public.tickets (workspace_id, technician_id, created_at DESC);

-- Partial Index for Kanban (Active Tickets)
-- "Active" defined as: Not Delivered AND Not Deleted.
CREATE INDEX IF NOT EXISTS idx_tickets_active_kanban ON public.tickets (workspace_id, status, created_at DESC)
WHERE delivered_at IS NULL AND deleted_at IS NULL;

-- Index for Deleted items
CREATE INDEX IF NOT EXISTS idx_tickets_deleted_at ON public.tickets (deleted_at);

-- 3. Dashboard KPI Function
CREATE OR REPLACE FUNCTION public.get_dashboard_kpis(
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL,
    p_technician_id UUID DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_defect TEXT DEFAULT NULL,
    p_device_model TEXT DEFAULT NULL,
    p_search TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER -- Critical: Respects RLS policies of the caller
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- The query relies on RLS to filter by workspace_id automatically.
    -- We effectively select from 'tickets' and let Postgres apply policies.

    WITH filtered_tickets AS (
        SELECT
            t.*,
            -- Normalize repair timestamp for daily counts
            COALESCE(t.repair_end_at, CASE WHEN t.status = 'Finalizado' THEN t.updated_at ELSE NULL END) as effective_repair_end,
            -- Calculate Durations (in seconds)
            EXTRACT(EPOCH FROM (t.repair_end_at - t.repair_start_at)) as duration_repair_sec,
            EXTRACT(EPOCH FROM (COALESCE(t.pickup_available_at, t.repair_end_at) - t.created_at)) as duration_solution_sec,
            EXTRACT(EPOCH FROM (t.delivered_at - t.created_at)) as duration_delivery_sec,
            EXTRACT(EPOCH FROM (t.budget_sent_at - t.created_at)) as duration_budget_sec,
            EXTRACT(EPOCH FROM (t.pickup_available_at - t.created_at)) as duration_pickup_notify_sec
        FROM
            public.tickets t
        WHERE
            t.deleted_at IS NULL -- Always exclude deleted
            -- Date Filters (created_at)
            AND (p_date_start IS NULL OR t.created_at >= p_date_start::timestamp)
            AND (p_date_end IS NULL OR t.created_at <= (p_date_end::timestamp + INTERVAL '1 day' - INTERVAL '1 millisecond'))
            -- Technician Filter
            AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
            -- Status Filter
            AND (p_status IS NULL OR p_status = 'all' OR t.status = p_status)
            -- Model Filter
            AND (p_device_model IS NULL OR p_device_model = 'all' OR t.device_model = p_device_model)
            -- Defect Filter (Approximate string match or exact if normalized)
            AND (p_defect IS NULL OR p_defect = 'all' OR t.defect_reported ILIKE '%' || p_defect || '%')
            -- Search Filter (Optional)
            AND (p_search IS NULL OR
                 t.client_name ILIKE '%' || p_search || '%' OR
                 t.os_number ILIKE '%' || p_search || '%' OR
                 t.device_model ILIKE '%' || p_search || '%' OR
                 t.serial_number ILIKE '%' || p_search || '%' OR
                 t.contact_info ILIKE '%' || p_search || '%'
            )
    ),
    -- Expand Defects for "Top Defects"
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
    -- Aggregations
    stats AS (
        SELECT
            count(*) as total_tickets,
            count(*) FILTER (WHERE status = 'Analise Tecnica') as analysis_count,
            count(*) FILTER (WHERE status = 'Andamento Reparo') as repair_count,

            -- Success Rate
            count(*) FILTER (WHERE repair_successful IS NOT NULL) as total_with_outcome,
            count(*) FILTER (WHERE repair_successful = TRUE) as success_count,

            -- Averages (Seconds)
            avg(duration_repair_sec) FILTER (WHERE duration_repair_sec > 0) as avg_repair_sec,
            avg(duration_solution_sec) FILTER (WHERE duration_solution_sec > 0) as avg_solution_sec,
            avg(duration_delivery_sec) FILTER (WHERE duration_delivery_sec > 0) as avg_delivery_sec,
            avg(duration_budget_sec) FILTER (WHERE duration_budget_sec > 0) as avg_budget_sec,
            avg(duration_pickup_notify_sec) FILTER (WHERE duration_pickup_notify_sec > 0) as avg_pickup_notify_sec,

            -- Time-based Counts
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '1 day')) as tickets_today,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '7 days')) as tickets_week,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '30 days')) as tickets_month,

            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '1 day')) as repairs_today,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '7 days')) as repairs_week,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '30 days')) as repairs_month,

            -- Logistics Stats
            count(*) FILTER (WHERE delivery_method = 'pickup') as pickup_total,
            count(*) FILTER (WHERE delivery_method = 'pickup' AND repair_successful = TRUE) as pickup_success,
            count(*) FILTER (WHERE delivery_method = 'pickup' AND repair_successful = FALSE) as pickup_fail,

            count(*) FILTER (WHERE delivery_method = 'carrier') as carrier_total,
            count(*) FILTER (WHERE delivery_method = 'carrier' AND repair_successful = TRUE) as carrier_success,
            count(*) FILTER (WHERE delivery_method = 'carrier' AND repair_successful = FALSE) as carrier_fail,

            -- Outsourced vs Internal
            count(*) FILTER (WHERE is_outsourced = TRUE) as outsourced_total,
            count(*) FILTER (WHERE is_outsourced = TRUE AND repair_successful = TRUE) as outsourced_success,
            count(*) FILTER (WHERE is_outsourced = TRUE AND repair_successful = FALSE) as outsourced_fail,
            sum(COALESCE(outsourced_return_count, 0)) as outsourced_returns,

            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto')) as internal_total,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto') AND repair_successful = TRUE) as internal_success,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto') AND repair_successful = FALSE) as internal_fail
        FROM filtered_tickets
    ),
    -- Top Defects
    top_defects AS (
        SELECT
            defect_name as label,
            count(*) as total,
            count(*) FILTER (WHERE repair_successful = TRUE) as success,
            count(*) FILTER (WHERE repair_successful = FALSE) as fail,
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate",
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate"
        FROM expanded_defects
        GROUP BY defect_name
        ORDER BY total DESC
    ),
    -- Top Models
    top_models AS (
        SELECT
            device_model as label,
            count(*) as total,
            count(*) FILTER (WHERE repair_successful = TRUE) as success,
            count(*) FILTER (WHERE repair_successful = FALSE) as fail,
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate",
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate"
        FROM filtered_tickets
        WHERE device_model IS NOT NULL
        GROUP BY device_model
        ORDER BY total DESC
    ),
    -- Top Combos
    top_combos AS (
        SELECT
            device_model || ' · ' || defect_name as label,
            count(*) as total,
            count(*) FILTER (WHERE repair_successful = TRUE) as success,
            count(*) FILTER (WHERE repair_successful = FALSE) as fail,
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate",
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate"
        FROM expanded_defects
        WHERE device_model IS NOT NULL
        GROUP BY device_model, defect_name
        ORDER BY total DESC
    ),
    -- Tech Stats
    tech_metrics AS (
        SELECT
            t.technician_id,
            count(*) as total,
            count(*) FILTER (WHERE t.repair_successful IS NOT NULL) as completed,
            count(*) FILTER (WHERE t.repair_successful = TRUE) as success_count
        FROM filtered_tickets t
        WHERE t.technician_id IS NOT NULL
        GROUP BY t.technician_id
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

            'ticketsPerDay', CASE
                WHEN p_date_start IS NOT NULL AND p_date_end IS NOT NULL
                THEN round((SELECT total_tickets FROM stats)::numeric / GREATEST(1, EXTRACT(DAY FROM (p_date_end::timestamp - p_date_start::timestamp))))
                ELSE 0
            END,

            'repairsToday', (SELECT repairs_today FROM stats),
            'repairsWeek', (SELECT repairs_week FROM stats),
            'repairsMonth', (SELECT repairs_month FROM stats),

            'ticketsToday', (SELECT tickets_today FROM stats),
            'ticketsWeek', (SELECT tickets_week FROM stats),
            'ticketsMonth', (SELECT tickets_month FROM stats),

            'topDefects', (SELECT COALESCE(jsonb_agg(d), '[]'::jsonb) FROM (SELECT * FROM top_defects) d),
            'topModels', (SELECT COALESCE(jsonb_agg(m), '[]'::jsonb) FROM (SELECT * FROM top_models LIMIT 100) m),
            'topCombos', (SELECT COALESCE(jsonb_agg(c), '[]'::jsonb) FROM (SELECT * FROM top_combos LIMIT 50) c),

            'techStats', (SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
                 SELECT tm.technician_id as id,
                        e.name,
                        tm.total,
                        tm.completed,
                        CASE WHEN tm.completed > 0 THEN round((tm.success_count::numeric / tm.completed) * 100) ELSE 0 END as "successRate"
                 FROM tech_metrics tm
                 LEFT JOIN public.employees e ON e.id = tm.technician_id
                 ORDER BY tm.completed DESC
            ) t),

            -- Slowest/Fastest lists (Simplified to top 5)
            'slowestModels', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                SELECT device_model as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count
                FROM filtered_tickets WHERE duration_repair_sec > 0
                GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5
            ) x),
            'slowestModelsSolution', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                SELECT device_model as label, avg(duration_solution_sec) * 1000 as "avgTime", count(*) as count
                FROM filtered_tickets WHERE duration_solution_sec > 0
                GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5
            ) x),
            'slowestModelsDelivery', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                SELECT device_model as label, avg(duration_delivery_sec) * 1000 as "avgTime", count(*) as count
                FROM filtered_tickets WHERE duration_delivery_sec > 0
                GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5
            ) x),

             'slowestDefects', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                SELECT defect_name as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count
                FROM expanded_defects WHERE duration_repair_sec > 0
                GROUP BY defect_name ORDER BY "avgTime" DESC LIMIT 5
            ) x),
             'slowestCombos', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                SELECT device_model || ' - ' || defect_name as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count
                FROM expanded_defects WHERE duration_repair_sec > 0
                GROUP BY label ORDER BY "avgTime" DESC LIMIT 5
            ) x),

             -- Logistics Stats
            'logisticsStats', jsonb_build_object(
                'pickup', jsonb_build_object('total', (SELECT pickup_total FROM stats), 'success', (SELECT pickup_success FROM stats), 'fail', (SELECT pickup_fail FROM stats)),
                'carrier', jsonb_build_object('total', (SELECT carrier_total FROM stats), 'success', (SELECT carrier_success FROM stats), 'fail', (SELECT carrier_fail FROM stats))
            ),
             -- Outsourced Stats
            'outsourcedStats', jsonb_build_object(
                'total', (SELECT outsourced_total FROM stats),
                'success', (SELECT outsourced_success FROM stats),
                'fail', (SELECT outsourced_fail FROM stats),
                'returns', (SELECT outsourced_returns FROM stats)
            ),
            'internalStats', jsonb_build_object(
                'total', (SELECT internal_total FROM stats),
                'success', (SELECT internal_success FROM stats),
                'fail', (SELECT internal_fail FROM stats)
            )

        ) INTO v_result;

    RETURN v_result;
END;
$$;

-- 4. Permissions
GRANT EXECUTE ON FUNCTION public.get_dashboard_kpis TO anon, authenticated;
