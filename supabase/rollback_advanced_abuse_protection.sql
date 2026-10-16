-- Revert only advanced abuse containment. Existing business records and Storage objects are untouched.
-- Bucket rollback restores only size/MIME: photos/logos NULL; inventory 5MB JPEG/PNG/WebP.
BEGIN;
DO $hook$
DECLARE v_hook text;
BEGIN
 SELECT split_part(c,'=',2) INTO v_hook FROM pg_catalog.pg_db_role_setting s CROSS JOIN LATERAL unnest(s.setconfig)c
 WHERE s.setrole=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticator')
 AND s.setdatabase=(SELECT oid FROM pg_catalog.pg_database WHERE datname=current_database())
 AND c LIKE 'pgrst.db_pre_request=%';
 IF coalesce(v_hook,'') NOT IN ('','private.check_request_budget') THEN
  RAISE EXCEPTION 'A different pre-request hook is configured; review rollback: %',v_hook;
 END IF;
 EXECUTE format('ALTER ROLE authenticator IN DATABASE %I RESET pgrst.db_pre_request',current_database());
END $hook$;
-- Restore only the two configuration columns captured before this migration.
UPDATE storage.buckets SET file_size_limit=NULL,allowed_mime_types=NULL
 WHERE id IN ('ticket_photos','workspace_logos');
UPDATE storage.buckets SET file_size_limit=5242880,allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp']::text[]
 WHERE id='inventory_images';
DROP POLICY IF EXISTS abuse_reserved_upload_insert ON storage.objects;
DROP POLICY IF EXISTS abuse_reserved_upload_update ON storage.objects;
CREATE OR REPLACE FUNCTION public.get_operational_queue(p_window text, p_basis text, p_status text DEFAULT NULL::text, p_technician_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 200, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
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

    SELECT ctx.workspace_id INTO v_workspace_id FROM public.get_current_actor_context() ctx;

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
$function$

;
CREATE OR REPLACE FUNCTION public.get_overview_queue_page(p_queue_key text, p_window text DEFAULT 'all'::text, p_basis text DEFAULT 'auto'::text, p_status text DEFAULT NULL::text, p_technician_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
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

    SELECT ctx.workspace_id INTO v_workspace_id FROM public.get_current_actor_context() ctx;

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
$function$

;
CREATE OR REPLACE FUNCTION public.get_inventory_movements_page(p_item_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_created_at timestamptz;
    v_id uuid;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');
    if p_limit < 1 or p_limit > 50 then raise exception 'Limite invalido.'; end if;
    if p_cursor is not null then
        begin
            v_created_at := (p_cursor ->> 'created_at')::timestamptz;
            v_id := (p_cursor ->> 'id')::uuid;
        exception when others then raise exception 'Cursor invalido.';
        end;
    end if;
    with page_plus_one as materialized (
        select m.id, m.item_id, i.name item_name, m.location_id,
               l.name location_name, m.movement_type, m.physical_delta,
               m.reserved_delta, m.physical_before, m.physical_after,
               m.reserved_before, m.reserved_after, m.ticket_id, t.os_number, m.purchase_id,
               m.reason, m.actor_name, m.created_at
        from public.inventory_movements m
        join public.inventory_items i
          on i.workspace_id = m.workspace_id and i.id = m.item_id
        join public.inventory_locations l
          on l.workspace_id = m.workspace_id and l.id = m.location_id
        left join public.tickets t
          on t.workspace_id = m.workspace_id and t.id = m.ticket_id
        where m.workspace_id = v_ctx.workspace_id
          and (p_item_id is null or m.item_id = p_item_id)
          and (p_cursor is null or (m.created_at, m.id) < (v_created_at, v_id))
        order by m.created_at desc, m.id desc
        limit p_limit + 1
    ), page_rows as (
        select * from page_plus_one order by created_at desc, id desc limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc, p.id desc) from page_rows p), '[]'::jsonb),
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (select jsonb_build_object('created_at', p.created_at, 'id', p.id)
                        from page_rows p order by p.created_at, p.id limit 1)
    ) into v_result;
    return v_result;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.set_inventory_item_locations(p_item_id uuid, p_location_ids uuid[], p_default_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_ctx record;v_id uuid;v_ids uuid[]:=coalesce(p_location_ids,array[]::uuid[]); begin select * into v_ctx from public.get_current_actor_context();perform private.inventory_assert_access(v_ctx.workspace_id,'admin');if not exists(select 1 from public.inventory_items i where i.workspace_id=v_ctx.workspace_id and i.id=p_item_id) then raise exception 'Item nao encontrado.';end if;if exists(select 1 from unnest(v_ids)x(id) where not exists(select 1 from public.inventory_locations l where l.workspace_id=v_ctx.workspace_id and l.id=x.id and l.active)) then raise exception 'Uma localizacao selecionada e invalida.';end if;if p_default_location_id is not null and not(p_default_location_id=any(v_ids)) then raise exception 'O local principal deve estar entre os locais selecionados.';end if;foreach v_id in array v_ids loop insert into public.inventory_balances(workspace_id,item_id,location_id,physical_quantity,reserved_quantity) values(v_ctx.workspace_id,p_item_id,v_id,0,0) on conflict(workspace_id,item_id,location_id) do nothing;end loop;delete from public.inventory_balances b where b.workspace_id=v_ctx.workspace_id and b.item_id=p_item_id and b.physical_quantity=0 and b.reserved_quantity=0 and not(b.location_id=any(v_ids));update public.inventory_items set default_location_id=p_default_location_id,updated_at=now() where workspace_id=v_ctx.workspace_id and id=p_item_id;return jsonb_build_object('success',true,'location_count',cardinality(v_ids));end;$function$

;
CREATE OR REPLACE FUNCTION public.cancel_workspace_invitation(p_invitation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_inv public.workspace_invitations%rowtype;
BEGIN
    SELECT * INTO v_inv FROM public.workspace_invitations WHERE id = p_invitation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Convite nao encontrado.' USING ERRCODE = '22023'; END IF;
    PERFORM private.assert_workspace_manager(v_inv.workspace_id);
    IF v_inv.status = 'accepted' THEN RAISE EXCEPTION 'Convite ja aceito; gerencie o vinculo do funcionario.' USING ERRCODE = '22023'; END IF;
    UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE id = p_invitation_id;
END $function$

;
CREATE OR REPLACE FUNCTION public.create_employee(p_workspace_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_new_id uuid;
begin
    if not public.can_manage_workspace(p_workspace_id) then
        raise exception 'Permissao negada.';
    end if;

    perform private.assert_employee_temporary_password(p_password);

    if nullif(btrim(p_name), '') is null or nullif(btrim(p_username), '') is null then
        raise exception 'Nome e usuario sao obrigatorios.';
    end if;

    insert into public.employees (
        workspace_id, name, username, password_hash, roles, must_change_password
    ) values (
        p_workspace_id,
        btrim(p_name),
        btrim(p_username),
        extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
        coalesce(p_roles, '{}'::text[]),
        true
    )
    returning id into v_new_id;

    return v_new_id;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.create_workspace_invitation(p_workspace_id uuid, p_name text, p_email text, p_roles text[], p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_employee uuid; v_id uuid; v_email text := lower(btrim(COALESCE(p_email, '')));
BEGIN
    PERFORM private.assert_workspace_manager(p_workspace_id);
    PERFORM private.assert_employee_roles(p_roles);
    IF char_length(btrim(COALESCE(p_name, ''))) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'Nome deve ter entre 2 e 80 caracteres.' USING ERRCODE = '22023'; END IF;
    IF length(v_email) > 254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'E-mail invalido.' USING ERRCODE = '22023'; END IF;
    IF EXISTS(SELECT 1 FROM public.workspace_memberships m JOIN auth.users u ON u.id = m.user_id
        WHERE m.workspace_id = p_workspace_id AND lower(btrim(u.email)) = v_email AND m.status <> 'revoked') THEN
        RAISE EXCEPTION 'Esta conta ja tem vinculo com a empresa.' USING ERRCODE = '23505';
    END IF;
    IF p_employee_id IS NULL THEN
        INSERT INTO public.employees(workspace_id, name, username, password_hash, roles, must_change_password)
        VALUES(p_workspace_id, btrim(p_name), 'auth_' || extensions.gen_random_uuid()::text,
            extensions.crypt(encode(extensions.gen_random_bytes(32), 'hex'), extensions.gen_salt('bf', 10)),
            ARRAY(SELECT DISTINCT r FROM unnest(p_roles) r ORDER BY r), false)
        RETURNING id INTO v_employee;
    ELSE
        SELECT e.id INTO v_employee FROM public.employees e WHERE e.id = p_employee_id AND e.workspace_id = p_workspace_id
            AND NOT e.legacy_auth_disabled AND e.deleted_at IS NULL FOR UPDATE;
        IF v_employee IS NULL OR EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = v_employee) THEN
            RAISE EXCEPTION 'Funcionario invalido ou ja associado.' USING ERRCODE = '42501';
        END IF;
        UPDATE public.employees SET name = btrim(p_name), roles = ARRAY(SELECT DISTINCT r FROM unnest(p_roles) r ORDER BY r) WHERE id = v_employee;
        UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE employee_id = v_employee AND status = 'pending';
    END IF;
    INSERT INTO public.workspace_invitations(workspace_id, employee_id, email, invited_by)
    VALUES(p_workspace_id, v_employee, v_email, auth.uid()) RETURNING id INTO v_id;
    RETURN v_id;
END $function$

;
CREATE OR REPLACE FUNCTION public.reissue_workspace_invitation(p_invitation_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_inv public.workspace_invitations%rowtype; v_id uuid;
BEGIN
    SELECT * INTO v_inv FROM public.workspace_invitations WHERE id = p_invitation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Convite nao encontrado.' USING ERRCODE = '22023'; END IF;
    PERFORM private.assert_workspace_manager(v_inv.workspace_id);
    IF v_inv.status = 'accepted' OR EXISTS(SELECT 1 FROM public.workspace_memberships WHERE employee_id = v_inv.employee_id) THEN
        RAISE EXCEPTION 'Funcionario ja associado.' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.employees WHERE id = v_inv.employee_id AND deleted_at IS NULL AND NOT legacy_auth_disabled) THEN
        RAISE EXCEPTION 'Funcionario removido.' USING ERRCODE = '22023';
    END IF;
    UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE employee_id = v_inv.employee_id AND status = 'pending';
    INSERT INTO public.workspace_invitations(workspace_id, employee_id, email, invited_by)
    VALUES(v_inv.workspace_id, v_inv.employee_id, v_inv.email, auth.uid()) RETURNING id INTO v_id;
    RETURN v_id;
END $function$

;
CREATE OR REPLACE FUNCTION public.revoke_employee_sessions(p_employee_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_workspace uuid; v_count integer;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    UPDATE public.workspace_memberships SET session_valid_after = now() WHERE employee_id = p_employee_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $function$

;
CREATE OR REPLACE FUNCTION public.set_employee_account_blocked(p_employee_id uuid, p_blocked boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_workspace uuid;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    IF p_blocked IS NULL THEN RAISE EXCEPTION 'Estado de bloqueio obrigatorio.' USING ERRCODE = '22023'; END IF;
    IF p_blocked AND EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = p_employee_id AND m.user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Voce nao pode bloquear seu proprio acesso.' USING ERRCODE = '42501'; END IF;
    IF length(p_reason) > 500 THEN RAISE EXCEPTION 'Motivo muito longo.' USING ERRCODE = '22023'; END IF;
    INSERT INTO public.employee_auth_state(employee_id, manual_blocked, manual_blocked_at, manual_block_reason)
    VALUES(p_employee_id, p_blocked, CASE WHEN p_blocked THEN now() END, CASE WHEN p_blocked THEN NULLIF(btrim(p_reason), '') END)
    ON CONFLICT(employee_id) DO UPDATE SET manual_blocked = excluded.manual_blocked, manual_blocked_at = excluded.manual_blocked_at,
        manual_block_reason = excluded.manual_block_reason, updated_at = now();
    UPDATE public.workspace_memberships SET status = CASE WHEN p_blocked THEN 'blocked' ELSE 'active' END,
        session_valid_after = CASE WHEN p_blocked THEN now() ELSE session_valid_after END
    WHERE employee_id = p_employee_id AND status <> 'revoked';
END $function$

;
CREATE OR REPLACE FUNCTION public.set_employee_removed(p_employee_id uuid, p_removed boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_workspace uuid;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    IF p_removed IS NULL THEN RAISE EXCEPTION 'Estado de remocao obrigatorio.' USING ERRCODE = '22023'; END IF;
    IF p_removed AND EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = p_employee_id AND m.user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Voce nao pode remover seu proprio acesso.' USING ERRCODE = '42501'; END IF;
    UPDATE public.employees SET deleted_at = CASE WHEN p_removed THEN now() END WHERE id = p_employee_id;
    UPDATE public.workspace_memberships SET status = CASE WHEN p_removed THEN 'revoked'
        WHEN EXISTS(SELECT 1 FROM public.employee_auth_state a WHERE a.employee_id = p_employee_id AND a.manual_blocked) THEN 'blocked' ELSE 'active' END,
        session_valid_after = CASE WHEN p_removed THEN now() ELSE session_valid_after END WHERE employee_id = p_employee_id;
    IF p_removed THEN UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE employee_id = p_employee_id AND status = 'pending'; END IF;
END $function$

;
CREATE OR REPLACE FUNCTION public.update_employee(p_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_workspace_id uuid;
begin
    select e.workspace_id into v_workspace_id
    from public.employees e where e.id = p_id;

    if v_workspace_id is null then
        raise exception 'Funcionario nao encontrado.';
    end if;
    if not public.can_manage_workspace(v_workspace_id) then
        raise exception 'Permissao negada.';
    end if;
    if nullif(btrim(p_name), '') is null or nullif(btrim(p_username), '') is null then
        raise exception 'Nome e usuario sao obrigatorios.';
    end if;
    if p_password is not null and p_password <> '' then
        perform private.assert_employee_temporary_password(p_password);
    end if;

    update public.employees
    set name = btrim(p_name),
        username = btrim(p_username),
        password_hash = case
            when p_password is not null and p_password <> ''
            then extensions.crypt(p_password, extensions.gen_salt('bf', 10))
            else password_hash
        end,
        must_change_password = case
            when p_password is not null and p_password <> '' then true
            else must_change_password
        end,
        roles = coalesce(p_roles, '{}'::text[])
    where id = p_id;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.update_employee_access(p_employee_id uuid, p_name text, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_workspace uuid;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    PERFORM private.assert_employee_roles(p_roles);
    IF char_length(btrim(COALESCE(p_name, ''))) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'Nome deve ter entre 2 e 80 caracteres.' USING ERRCODE = '22023'; END IF;
    IF EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = p_employee_id AND m.user_id = auth.uid())
       AND NOT 'admin' = ANY(p_roles) THEN RAISE EXCEPTION 'Voce nao pode remover sua propria permissao administrativa.' USING ERRCODE = '42501'; END IF;
    UPDATE public.employees SET name = btrim(p_name), roles = ARRAY(SELECT DISTINCT r FROM unnest(p_roles) r ORDER BY r) WHERE id = p_employee_id;
END $function$

;
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
    AND t.deleted_at IS NULL
    AND public.aida_config_bool(COALESCE(w.tracker_config, '{}'::jsonb), 'modules', 'public_tracker', true);
END;
$function$

;
CREATE OR REPLACE FUNCTION public.get_client_ticket_details_public_configurable(p_ticket_id uuid, p_public_token uuid)
 RETURNS TABLE(id uuid, os_number text, device_model text, status text, deadline timestamp with time zone, priority_requested boolean, pickup_available boolean, created_at timestamp with time zone, whatsapp_number text, tracker_config jsonb, delivery_method text, carrier_name text, tracking_code text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    SELECT d.*
    FROM public.tickets t
    JOIN public.workspaces w ON w.id = t.workspace_id
    CROSS JOIN LATERAL public.get_client_ticket_details_public(p_ticket_id, p_public_token) d
    WHERE t.id = p_ticket_id
      AND t.public_token = p_public_token
      AND t.deleted_at IS NULL
      AND public.aida_config_bool(COALESCE(w.tracker_config, '{}'::jsonb), 'modules', 'public_tracker', true);
$function$
;
DROP FUNCTION IF EXISTS public.reserve_storage_upload(text,text,bigint,text);
DROP FUNCTION IF EXISTS public.consume_edge_request_budget(text,uuid);
DROP FUNCTION IF EXISTS private.check_public_tracker_budget(uuid);
DROP FUNCTION IF EXISTS private.has_storage_upload_reservation(text,text);
DROP FUNCTION IF EXISTS private.consume_team_budget(uuid);
DROP FUNCTION IF EXISTS private.check_request_budget();
DROP FUNCTION IF EXISTS private.acquire_request_slots(text,text,integer);
DROP FUNCTION IF EXISTS private.consume_request_budget(text,text,integer,integer);
DROP FUNCTION IF EXISTS private.raise_request_limit(text,integer);
DROP TABLE IF EXISTS private.storage_upload_reservations;
DROP TABLE IF EXISTS private.request_budgets;
DROP TABLE IF EXISTS private.abuse_settings;
REVOKE USAGE ON SCHEMA private FROM anon,authenticator;
NOTIFY pgrst,'reload config';
NOTIFY pgrst,'reload schema';
COMMIT;

