-- Create targeted partial indices for performance
CREATE INDEX IF NOT EXISTS idx_tickets_analysis_deadline
ON public.tickets (workspace_id, status, analysis_deadline)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_tickets_deadline
ON public.tickets (workspace_id, status, deadline)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_tickets_outsourced_deadline
ON public.tickets (workspace_id, status, outsourced_deadline)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_tickets_tech_created
ON public.tickets (workspace_id, technician_id, created_at)
WHERE deleted_at IS NULL;


-- Create the function
CREATE OR REPLACE FUNCTION public.get_operational_queue(
  p_window text default 'today',
  p_basis text default 'auto',
  p_status text default null,
  p_technician_id uuid default null,
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_workspace_id UUID;
    v_user_id UUID;

    v_tz TEXT := 'America/Sao_Paulo';
    v_today_date DATE;
    v_today_start TIMESTAMP WITH TIME ZONE;
    v_tomorrow_start TIMESTAMP WITH TIME ZONE;
    v_day_after_tomorrow_start TIMESTAMP WITH TIME ZONE;
    v_in_8_days_start TIMESTAMP WITH TIME ZONE;

    v_result JSONB;
    v_counts JSONB;
    v_items JSONB;
BEGIN
    -- 1. Parameter Validation
    IF p_window NOT IN ('today', 'today_tomorrow', 'next_7_days', 'overdue', 'no_deadline', 'all') THEN
        RAISE EXCEPTION 'Parâmetro p_window inválido. Permitidos: today, today_tomorrow, next_7_days, overdue, no_deadline, all';
    END IF;

    IF p_basis NOT IN ('auto', 'analysis', 'delivery', 'entry', 'outsourced') THEN
        RAISE EXCEPTION 'Parâmetro p_basis inválido. Permitidos: auto, analysis, delivery, entry, outsourced';
    END IF;

    IF p_limit < 0 OR p_limit > 200 THEN
        RAISE EXCEPTION 'Parâmetro p_limit deve estar entre 0 e 200.';
    END IF;

    IF p_offset < 0 THEN
        RAISE EXCEPTION 'Parâmetro p_offset não pode ser negativo.';
    END IF;

    -- 2. Secure Workspace Resolution
    v_user_id := auth.uid();

    IF v_user_id IS NOT NULL THEN
        -- Try to find in profiles
        SELECT workspace_id INTO v_workspace_id
        FROM public.profiles
        WHERE id = v_user_id;

        -- Try to find in workspaces directly (if owner)
        IF v_workspace_id IS NULL THEN
            SELECT id INTO v_workspace_id
            FROM public.workspaces
            WHERE owner_id = v_user_id
            LIMIT 1;
        END IF;
    END IF;

    -- If not resolved yet, use the standard system function for employee tokens
    IF v_workspace_id IS NULL THEN
        BEGIN
            SELECT workspace_id INTO v_workspace_id
            FROM public.current_employee_from_token()
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_workspace_id := NULL;
        END;
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: Workspace não resolvido ou inválido.';
    END IF;

    -- 3. Time Calculations in Operation Timezone
    -- Get current date in Sao Paulo timezone safely
    v_today_date := (now() AT TIME ZONE v_tz)::date;

    -- Convert local date back to absolute timestamptz for boundaries
    -- This casts the local date to a local timestamp 'YYYY-MM-DD 00:00:00'
    -- and then correctly interprets it as America/Sao_Paulo time to produce a global timestamptz.
    v_today_start := (v_today_date::timestamp AT TIME ZONE v_tz);
    v_tomorrow_start := v_today_start + interval '1 day';
    v_day_after_tomorrow_start := v_today_start + interval '2 days';
    v_in_8_days_start := v_today_start + interval '8 days';

    -- 4. Calculate everything and retrieve counts and items
    WITH base_tickets AS (
        SELECT
            t.*,
            -- Effective Due At and Type Logic
            CASE
                WHEN p_basis = 'analysis' THEN t.analysis_deadline
                WHEN p_basis = 'delivery' THEN t.deadline
                WHEN p_basis = 'entry' THEN t.entry_date
                WHEN p_basis = 'outsourced' THEN t.outsourced_deadline
                WHEN p_basis = 'auto' THEN
                    CASE
                        WHEN t.status = 'Terceirizado' AND t.outsourced_deadline IS NOT NULL THEN t.outsourced_deadline
                        WHEN t.status IN ('Aberto', 'Analise Tecnica') AND t.analysis_deadline IS NOT NULL THEN t.analysis_deadline
                        WHEN t.status IN ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente') AND t.deadline IS NOT NULL THEN t.deadline
                        ELSE COALESCE(t.analysis_deadline, t.deadline, t.outsourced_deadline)
                    END
            END AS effective_due_at,

            CASE
                WHEN p_basis = 'analysis' AND t.analysis_deadline IS NOT NULL THEN 'analysis'
                WHEN p_basis = 'delivery' AND t.deadline IS NOT NULL THEN 'delivery'
                WHEN p_basis = 'entry' AND t.entry_date IS NOT NULL THEN 'entry'
                WHEN p_basis = 'outsourced' AND t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                WHEN p_basis = 'auto' THEN
                    CASE
                        WHEN t.status = 'Terceirizado' AND t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                        WHEN t.status IN ('Aberto', 'Analise Tecnica') AND t.analysis_deadline IS NOT NULL THEN 'analysis'
                        WHEN t.status IN ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente') AND t.deadline IS NOT NULL THEN 'delivery'
                        WHEN t.analysis_deadline IS NOT NULL THEN 'analysis'
                        WHEN t.deadline IS NOT NULL THEN 'delivery'
                        WHEN t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                        ELSE 'none'
                    END
                ELSE 'none'
            END AS effective_due_type
        FROM public.tickets t
        WHERE t.workspace_id = v_workspace_id
          AND t.deleted_at IS NULL
          AND (
              (p_status IS NULL AND t.status <> 'Finalizado')
              OR
              (p_status = 'all' AND t.status <> 'Finalizado')
              OR
              (p_status IS NOT NULL AND p_status <> 'all' AND t.status = p_status)
          )
          AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
          AND (
              p_search IS NULL OR p_search = ''
              OR t.client_name ILIKE '%' || p_search || '%'
              OR t.os_number ILIKE '%' || p_search || '%'
              OR t.device_model ILIKE '%' || p_search || '%'
              OR t.serial_number ILIKE '%' || p_search || '%'
              OR t.contact_info ILIKE '%' || p_search || '%'
          )
    ),
    bucketed_tickets AS (
        SELECT
            bt.*,
            -- Bucket Logic
            CASE
                WHEN bt.effective_due_at IS NULL THEN 'no_deadline'
                WHEN bt.effective_due_at < v_today_start THEN 'overdue'
                WHEN bt.effective_due_at >= v_today_start AND bt.effective_due_at < v_tomorrow_start THEN 'today'
                WHEN bt.effective_due_at >= v_tomorrow_start AND bt.effective_due_at < v_day_after_tomorrow_start THEN 'tomorrow'
                WHEN bt.effective_due_at >= v_day_after_tomorrow_start AND bt.effective_due_at < v_in_8_days_start THEN 'next_7_days'
                ELSE 'later'
            END AS urgency_bucket,

            -- is_overdue and days_to_due based on local time difference
            (bt.effective_due_at < v_today_start) AS is_overdue,
            CASE
                WHEN bt.effective_due_at IS NOT NULL THEN
                    -- EXTRACT EPOCH / 86400 on truncated local dates gives exact days difference.
                    -- Simple DATE subtraction using AT TIME ZONE:
                    ((bt.effective_due_at AT TIME ZONE v_tz)::date - (v_today_start AT TIME ZONE v_tz)::date)
                ELSE NULL
            END AS days_to_due
        FROM base_tickets bt
    ),
    aggregated_counts AS (
        SELECT
            jsonb_build_object(
                'today', COALESCE(COUNT(*) FILTER (WHERE urgency_bucket = 'today'), 0),
                'today_tomorrow', COALESCE(COUNT(*) FILTER (WHERE urgency_bucket IN ('today', 'tomorrow')), 0),
                'next_7_days', COALESCE(COUNT(*) FILTER (WHERE urgency_bucket IN ('today', 'tomorrow', 'next_7_days')), 0),
                'overdue', COALESCE(COUNT(*) FILTER (WHERE urgency_bucket = 'overdue'), 0),
                'no_deadline', COALESCE(COUNT(*) FILTER (WHERE urgency_bucket = 'no_deadline'), 0),
                'all', COALESCE(COUNT(*), 0)
            ) AS counts
        FROM bucketed_tickets
    ),
    filtered_items AS (
        SELECT COALESCE(jsonb_agg(row_to_json(filtered.*)), '[]'::jsonb) AS items
        FROM (
            SELECT * FROM bucketed_tickets ft
            WHERE
                (p_window = 'all') OR
                (p_window = 'overdue' AND ft.urgency_bucket = 'overdue') OR
                (p_window = 'no_deadline' AND ft.urgency_bucket = 'no_deadline') OR
                (p_window = 'today' AND ft.urgency_bucket = 'today') OR
                (p_window = 'today_tomorrow' AND ft.urgency_bucket IN ('today', 'tomorrow')) OR
                (p_window = 'next_7_days' AND ft.urgency_bucket IN ('today', 'tomorrow', 'next_7_days'))
            ORDER BY
                ft.effective_due_at ASC NULLS LAST,
                -- Safe and strict ordering based on actual columns
                ft.priority_requested DESC NULLS LAST,
                CASE ft.priority
                    WHEN 'Urgente' THEN 1
                    WHEN 'Alta' THEN 2
                    WHEN 'Normal' THEN 3
                    WHEN 'Baixa' THEN 4
                    ELSE 5
                END ASC,
                ft.created_at ASC
            LIMIT p_limit OFFSET p_offset
        ) filtered
    )
    SELECT
        (SELECT counts FROM aggregated_counts),
        (SELECT items FROM filtered_items)
    INTO v_counts, v_items;

    v_result := jsonb_build_object(
        'counts', v_counts,
        'items', v_items
    );

    RETURN v_result;
END;
$$;

-- Security Grants
REVOKE ALL ON FUNCTION public.get_operational_queue(text, text, text, uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_operational_queue(text, text, text, uuid, text, integer, integer) TO anon, authenticated;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
