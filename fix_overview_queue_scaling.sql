BEGIN;
-- Scales the Overview dashboard without loading every active ticket.
-- The existing operational queue RPC remains backward compatible for Kanban callers,
-- while p_limit = 0 now returns exact queue totals and five preview items per queue.

CREATE OR REPLACE FUNCTION public.get_operational_queue(
    p_window text,
    p_basis text,
    p_status text DEFAULT NULL::text,
    p_technician_id uuid DEFAULT NULL::uuid,
    p_search text DEFAULT NULL::text,
    p_limit integer DEFAULT 200,
    p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_workspace_id uuid;
    v_user_id uuid;
    v_tz text := 'America/Sao_Paulo';
    v_today_date date;
    v_today_start timestamptz;
    v_tomorrow_start timestamptz;
    v_day_after_tomorrow_start timestamptz;
    v_in_8_days_start timestamptz;
    v_counts jsonb;
    v_status_counts jsonb;
    v_items jsonb;
    v_queues jsonb;
BEGIN
    IF p_window NOT IN ('today', 'today_tomorrow', 'next_7_days', 'overdue', 'no_deadline', 'all') THEN
        RAISE EXCEPTION 'Parâmetro p_window inválido.';
    END IF;

    IF p_basis NOT IN ('auto', 'analysis', 'delivery', 'entry', 'outsourced') THEN
        RAISE EXCEPTION 'Parâmetro p_basis inválido.';
    END IF;

    IF p_limit < 0 OR p_limit > 200 THEN
        RAISE EXCEPTION 'Parâmetro p_limit deve estar entre 0 e 200.';
    END IF;

    IF p_offset < 0 THEN
        RAISE EXCEPTION 'Parâmetro p_offset não pode ser negativo.';
    END IF;

    v_user_id := auth.uid();

    IF v_user_id IS NOT NULL THEN
        SELECT workspace_id
        INTO v_workspace_id
        FROM public.profiles
        WHERE id = v_user_id;

        IF v_workspace_id IS NULL THEN
            SELECT id
            INTO v_workspace_id
            FROM public.workspaces
            WHERE owner_id = v_user_id
            LIMIT 1;
        END IF;
    END IF;

    IF v_workspace_id IS NULL THEN
        BEGIN
            SELECT workspace_id
            INTO v_workspace_id
            FROM public.current_employee_from_token()
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_workspace_id := NULL;
        END;
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: Workspace não resolvido ou inválido.';
    END IF;

    v_today_date := (now() AT TIME ZONE v_tz)::date;
    v_today_start := v_today_date::timestamp AT TIME ZONE v_tz;
    v_tomorrow_start := v_today_start + interval '1 day';
    v_day_after_tomorrow_start := v_today_start + interval '2 days';
    v_in_8_days_start := v_today_start + interval '8 days';

    WITH base_tickets AS (
        SELECT
            t.*,
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
              OR (p_status = 'all' AND t.status <> 'Finalizado')
              OR (p_status IS NOT NULL AND p_status <> 'all' AND t.status = p_status)
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
            CASE
                WHEN bt.effective_due_at IS NULL THEN 'no_deadline'
                WHEN bt.effective_due_at < v_today_start THEN 'overdue'
                WHEN bt.effective_due_at < v_tomorrow_start THEN 'today'
                WHEN bt.effective_due_at < v_day_after_tomorrow_start THEN 'tomorrow'
                WHEN bt.effective_due_at < v_in_8_days_start THEN 'next_7_days'
                ELSE 'later'
            END AS urgency_bucket,
            COALESCE(bt.effective_due_at < v_today_start, false) AS is_overdue,
            CASE
                WHEN bt.effective_due_at IS NOT NULL THEN
                    (bt.effective_due_at AT TIME ZONE v_tz)::date - (v_today_start AT TIME ZONE v_tz)::date
                ELSE NULL
            END AS days_to_due
        FROM base_tickets bt
    ),
    windowed_tickets AS (
        SELECT *
        FROM bucketed_tickets ft
        WHERE p_window = 'all'
           OR (p_window = 'overdue' AND ft.urgency_bucket = 'overdue')
           OR (p_window = 'no_deadline' AND ft.urgency_bucket = 'no_deadline')
           OR (p_window = 'today' AND ft.urgency_bucket = 'today')
           OR (p_window = 'today_tomorrow' AND ft.urgency_bucket IN ('today', 'tomorrow'))
           OR (p_window = 'next_7_days' AND ft.urgency_bucket IN ('today', 'tomorrow', 'next_7_days'))
    ),
    aggregated_counts AS (
        SELECT jsonb_build_object(
            'today', count(*) FILTER (WHERE urgency_bucket = 'today'),
            'today_tomorrow', count(*) FILTER (WHERE urgency_bucket IN ('today', 'tomorrow')),
            'next_7_days', count(*) FILTER (WHERE urgency_bucket IN ('today', 'tomorrow', 'next_7_days')),
            'overdue', count(*) FILTER (WHERE urgency_bucket = 'overdue'),
            'no_deadline', count(*) FILTER (WHERE urgency_bucket = 'no_deadline'),
            'all', count(*)
        ) AS counts
        FROM bucketed_tickets
    ),
    status_counts AS (
        SELECT jsonb_build_object(
            'open', count(*),
            'analysis', count(*) FILTER (WHERE status = 'Analise Tecnica'),
            'approval', count(*) FILTER (WHERE status = 'Aprovacao'),
            'pickup', count(*) FILTER (WHERE status = 'Retirada Cliente')
        ) AS counts
        FROM bucketed_tickets
    ),
    filtered_items AS (
        SELECT COALESCE(jsonb_agg(row_to_json(filtered.*)), '[]'::jsonb) AS items
        FROM (
            SELECT *
            FROM windowed_tickets ft
            ORDER BY
                ft.effective_due_at ASC NULLS LAST,
                ft.priority_requested DESC NULLS LAST,
                CASE ft.priority
                    WHEN 'Urgente' THEN 1
                    WHEN 'Alta' THEN 2
                    WHEN 'Normal' THEN 3
                    WHEN 'Baixa' THEN 4
                    ELSE 5
                END,
                ft.created_at,
                ft.id
            LIMIT p_limit OFFSET p_offset
        ) filtered
    ),
    module_rows AS (
        SELECT
            wt.*,
            CASE wt.overview_queue_stage
                WHEN 'budget_send_pending' THEN 'pendingBudgets'
                WHEN 'budget_approval_pending' THEN 'waitingBudgetResponse'
                WHEN 'pickup_pending' THEN 'pendingPickups'
                WHEN 'tracking_pending' THEN 'pendingTracking'
                WHEN 'delivery_pending' THEN 'pendingDelivery'
                WHEN 'analysis_start_pending' THEN 'pendingTech'
                WHEN 'outsourced_to_send' THEN 'outsourcedToSend'
                WHEN 'outsourced_waiting_return' THEN 'pendingOutsourced'
                WHEN 'parts_purchase_pending' THEN 'pendingPurchase'
                WHEN 'parts_receipt_pending' THEN 'pendingReceipt'
            END AS queue_key
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.overview_queue_stage IN (
              'budget_send_pending', 'budget_approval_pending', 'pickup_pending',
              'tracking_pending', 'delivery_pending', 'analysis_start_pending',
              'outsourced_to_send', 'outsourced_waiting_return',
              'parts_purchase_pending', 'parts_receipt_pending'
          )
    ),
    attention_rows AS (
        SELECT wt.*, 'priorityTickets'::text AS queue_key
        FROM windowed_tickets wt
        WHERE p_limit = 0 AND COALESCE(wt.priority_requested, false)

        UNION ALL
        SELECT wt.*, 'expiringDeliveries'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'delivery'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredDeliveries'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'delivery'
          AND wt.is_overdue

        UNION ALL
        SELECT wt.*, 'expiringAnalysis'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'analysis'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredAnalysis'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'analysis'
          AND wt.is_overdue
    ),
    queue_rows AS (
        SELECT * FROM module_rows
        UNION ALL
        SELECT * FROM attention_rows
    ),
    ranked_queues AS (
        SELECT
            qr.*,
            CASE
                WHEN COALESCE(qr.priority_requested, false) THEN 0
                WHEN qr.priority = 'Urgente' THEN 1
                WHEN qr.priority = 'Alta' THEN 2
                WHEN qr.priority = 'Normal' THEN 3
                WHEN qr.priority = 'Baixa' THEN 4
                ELSE 5
            END AS queue_priority_rank,
            COALESCE(qr.effective_due_at, 'infinity'::timestamptz) AS queue_due_sort,
            COALESCE(qr.overview_queue_entered_at, qr.updated_at, qr.created_at, qr.entry_date, 'infinity'::timestamptz) AS queue_entered_sort,
            row_number() OVER (
                PARTITION BY qr.queue_key
                ORDER BY
                    CASE
                        WHEN COALESCE(qr.priority_requested, false) THEN 0
                        WHEN qr.priority = 'Urgente' THEN 1
                        WHEN qr.priority = 'Alta' THEN 2
                        WHEN qr.priority = 'Normal' THEN 3
                        WHEN qr.priority = 'Baixa' THEN 4
                        ELSE 5
                    END,
                    COALESCE(qr.effective_due_at, 'infinity'::timestamptz),
                    COALESCE(qr.overview_queue_entered_at, qr.updated_at, qr.created_at, qr.entry_date, 'infinity'::timestamptz),
                    qr.created_at,
                    qr.id
            ) AS queue_row_number
        FROM queue_rows qr
    ),
    queue_rollup AS (
        SELECT
            queue_key,
            count(*) AS total,
            COALESCE(
                jsonb_agg(
                    to_jsonb(rq)
                    - 'queue_key'
                    - 'queue_priority_rank'
                    - 'queue_due_sort'
                    - 'queue_entered_sort'
                    - 'queue_row_number'
                    ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
                ) FILTER (WHERE queue_row_number <= 5),
                '[]'::jsonb
            ) AS items
        FROM ranked_queues rq
        GROUP BY queue_key
    ),
    queue_summary AS (
        SELECT COALESCE(
            jsonb_object_agg(
                queue_key,
                jsonb_build_object('total', total, 'items', items)
            ),
            '{}'::jsonb
        ) AS queues
        FROM queue_rollup
    )
    SELECT
        (SELECT counts FROM aggregated_counts),
        (SELECT counts FROM status_counts),
        (SELECT items FROM filtered_items),
        (SELECT queues FROM queue_summary)
    INTO v_counts, v_status_counts, v_items, v_queues;

    RETURN jsonb_build_object(
        'counts', COALESCE(v_counts, '{}'::jsonb),
        'status_counts', COALESCE(v_status_counts, '{}'::jsonb),
        'items', COALESCE(v_items, '[]'::jsonb),
        'queues', COALESCE(v_queues, '{}'::jsonb)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_overview_queue_page(
    p_queue_key text,
    p_window text DEFAULT 'all',
    p_basis text DEFAULT 'auto',
    p_status text DEFAULT NULL::text,
    p_technician_id uuid DEFAULT NULL::uuid,
    p_search text DEFAULT NULL::text,
    p_limit integer DEFAULT 20,
    p_cursor jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_workspace_id uuid;
    v_user_id uuid;
    v_tz text := 'America/Sao_Paulo';
    v_today_date date;
    v_today_start timestamptz;
    v_tomorrow_start timestamptz;
    v_day_after_tomorrow_start timestamptz;
    v_in_8_days_start timestamptz;
    v_total bigint;
    v_items jsonb;
    v_has_more boolean;
    v_next_cursor jsonb;
BEGIN
    IF p_queue_key NOT IN (
        'pendingBudgets', 'waitingBudgetResponse', 'pendingPickups',
        'pendingTracking', 'pendingDelivery', 'pendingTech',
        'outsourcedToSend', 'pendingOutsourced', 'pendingPurchase',
        'pendingReceipt', 'priorityTickets', 'expiringDeliveries',
        'expiredDeliveries', 'expiringAnalysis', 'expiredAnalysis'
    ) THEN
        RAISE EXCEPTION 'Fila da Visão Geral inválida.';
    END IF;

    IF p_window NOT IN ('today', 'today_tomorrow', 'next_7_days', 'overdue', 'no_deadline', 'all') THEN
        RAISE EXCEPTION 'Parâmetro p_window inválido.';
    END IF;

    IF p_basis NOT IN ('auto', 'analysis', 'delivery', 'entry', 'outsourced') THEN
        RAISE EXCEPTION 'Parâmetro p_basis inválido.';
    END IF;

    IF p_limit < 1 OR p_limit > 50 THEN
        RAISE EXCEPTION 'Parâmetro p_limit deve estar entre 1 e 50.';
    END IF;

    IF p_cursor IS NOT NULL
       AND NOT (p_cursor ?& ARRAY['priority_rank', 'due_sort', 'entered_sort', 'created_at', 'id']) THEN
        RAISE EXCEPTION 'Cursor de paginação inválido.';
    END IF;

    v_user_id := auth.uid();

    IF v_user_id IS NOT NULL THEN
        SELECT workspace_id
        INTO v_workspace_id
        FROM public.profiles
        WHERE id = v_user_id;

        IF v_workspace_id IS NULL THEN
            SELECT id
            INTO v_workspace_id
            FROM public.workspaces
            WHERE owner_id = v_user_id
            LIMIT 1;
        END IF;
    END IF;

    IF v_workspace_id IS NULL THEN
        BEGIN
            SELECT workspace_id
            INTO v_workspace_id
            FROM public.current_employee_from_token()
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_workspace_id := NULL;
        END;
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: Workspace não resolvido ou inválido.';
    END IF;

    v_today_date := (now() AT TIME ZONE v_tz)::date;
    v_today_start := v_today_date::timestamp AT TIME ZONE v_tz;
    v_tomorrow_start := v_today_start + interval '1 day';
    v_day_after_tomorrow_start := v_today_start + interval '2 days';
    v_in_8_days_start := v_today_start + interval '8 days';

    WITH base_tickets AS (
        SELECT
            t.*,
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
              OR (p_status = 'all' AND t.status <> 'Finalizado')
              OR (p_status IS NOT NULL AND p_status <> 'all' AND t.status = p_status)
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
            CASE
                WHEN bt.effective_due_at IS NULL THEN 'no_deadline'
                WHEN bt.effective_due_at < v_today_start THEN 'overdue'
                WHEN bt.effective_due_at < v_tomorrow_start THEN 'today'
                WHEN bt.effective_due_at < v_day_after_tomorrow_start THEN 'tomorrow'
                WHEN bt.effective_due_at < v_in_8_days_start THEN 'next_7_days'
                ELSE 'later'
            END AS urgency_bucket,
            COALESCE(bt.effective_due_at < v_today_start, false) AS is_overdue,
            CASE
                WHEN bt.effective_due_at IS NOT NULL THEN
                    (bt.effective_due_at AT TIME ZONE v_tz)::date - (v_today_start AT TIME ZONE v_tz)::date
                ELSE NULL
            END AS days_to_due
        FROM base_tickets bt
    ),
    windowed_tickets AS (
        SELECT *
        FROM bucketed_tickets ft
        WHERE p_window = 'all'
           OR (p_window = 'overdue' AND ft.urgency_bucket = 'overdue')
           OR (p_window = 'no_deadline' AND ft.urgency_bucket = 'no_deadline')
           OR (p_window = 'today' AND ft.urgency_bucket = 'today')
           OR (p_window = 'today_tomorrow' AND ft.urgency_bucket IN ('today', 'tomorrow'))
           OR (p_window = 'next_7_days' AND ft.urgency_bucket IN ('today', 'tomorrow', 'next_7_days'))
    ),
    module_rows AS (
        SELECT
            wt.*,
            CASE wt.overview_queue_stage
                WHEN 'budget_send_pending' THEN 'pendingBudgets'
                WHEN 'budget_approval_pending' THEN 'waitingBudgetResponse'
                WHEN 'pickup_pending' THEN 'pendingPickups'
                WHEN 'tracking_pending' THEN 'pendingTracking'
                WHEN 'delivery_pending' THEN 'pendingDelivery'
                WHEN 'analysis_start_pending' THEN 'pendingTech'
                WHEN 'outsourced_to_send' THEN 'outsourcedToSend'
                WHEN 'outsourced_waiting_return' THEN 'pendingOutsourced'
                WHEN 'parts_purchase_pending' THEN 'pendingPurchase'
                WHEN 'parts_receipt_pending' THEN 'pendingReceipt'
            END AS queue_key
        FROM windowed_tickets wt
        WHERE wt.overview_queue_stage IN (
            'budget_send_pending', 'budget_approval_pending', 'pickup_pending',
            'tracking_pending', 'delivery_pending', 'analysis_start_pending',
            'outsourced_to_send', 'outsourced_waiting_return',
            'parts_purchase_pending', 'parts_receipt_pending'
        )
    ),
    attention_rows AS (
        SELECT wt.*, 'priorityTickets'::text AS queue_key
        FROM windowed_tickets wt
        WHERE COALESCE(wt.priority_requested, false)

        UNION ALL
        SELECT wt.*, 'expiringDeliveries'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'delivery'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredDeliveries'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'delivery'
          AND wt.is_overdue

        UNION ALL
        SELECT wt.*, 'expiringAnalysis'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'analysis'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredAnalysis'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'analysis'
          AND wt.is_overdue
    ),
    queue_rows AS (
        SELECT * FROM module_rows
        UNION ALL
        SELECT * FROM attention_rows
    ),
    ordered_rows AS (
        SELECT
            qr.*,
            CASE
                WHEN COALESCE(qr.priority_requested, false) THEN 0
                WHEN qr.priority = 'Urgente' THEN 1
                WHEN qr.priority = 'Alta' THEN 2
                WHEN qr.priority = 'Normal' THEN 3
                WHEN qr.priority = 'Baixa' THEN 4
                ELSE 5
            END AS queue_priority_rank,
            COALESCE(qr.effective_due_at, 'infinity'::timestamptz) AS queue_due_sort,
            COALESCE(qr.overview_queue_entered_at, qr.updated_at, qr.created_at, qr.entry_date, 'infinity'::timestamptz) AS queue_entered_sort
        FROM queue_rows qr
        WHERE qr.queue_key = p_queue_key
    ),
    after_cursor AS (
        SELECT *
        FROM ordered_rows oq
        WHERE p_cursor IS NULL
           OR (
                oq.queue_priority_rank,
                oq.queue_due_sort,
                oq.queue_entered_sort,
                oq.created_at,
                oq.id
              ) > (
                (p_cursor->>'priority_rank')::integer,
                (p_cursor->>'due_sort')::timestamptz,
                (p_cursor->>'entered_sort')::timestamptz,
                (p_cursor->>'created_at')::timestamptz,
                (p_cursor->>'id')::uuid
              )
    ),
    page_plus_one AS (
        SELECT *
        FROM after_cursor
        ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
        LIMIT p_limit + 1
    ),
    page_rows AS (
        SELECT *
        FROM page_plus_one
        ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
        LIMIT p_limit
    )
    SELECT
        (SELECT count(*) FROM ordered_rows),
        COALESCE((
            SELECT jsonb_agg(
                to_jsonb(pr)
                - 'queue_key'
                - 'queue_priority_rank'
                - 'queue_due_sort'
                - 'queue_entered_sort'
                ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
            )
            FROM page_rows pr
        ), '[]'::jsonb),
        (SELECT count(*) > p_limit FROM page_plus_one),
        CASE
            WHEN (SELECT count(*) > p_limit FROM page_plus_one) THEN (
                SELECT jsonb_build_object(
                    'priority_rank', queue_priority_rank,
                    'due_sort', queue_due_sort,
                    'entered_sort', queue_entered_sort,
                    'created_at', created_at,
                    'id', id
                )
                FROM page_rows
                ORDER BY queue_priority_rank DESC, queue_due_sort DESC, queue_entered_sort DESC, created_at DESC, id DESC
                LIMIT 1
            )
            ELSE NULL
        END
    INTO v_total, v_items, v_has_more, v_next_cursor;

    RETURN jsonb_build_object(
        'total', COALESCE(v_total, 0),
        'items', COALESCE(v_items, '[]'::jsonb),
        'has_more', COALESCE(v_has_more, false),
        'next_cursor', v_next_cursor
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_operational_queue(text, text, text, uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_operational_queue(text, text, text, uuid, text, integer, integer)
    TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_overview_queue_page(text, text, text, text, uuid, text, integer, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_overview_queue_page(text, text, text, text, uuid, text, integer, jsonb)
    TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_overview_queue_page(text, text, text, text, uuid, text, integer, jsonb)
IS 'Returns one Overview queue with exact total and keyset pagination, scoped to the caller workspace.';
COMMIT;
