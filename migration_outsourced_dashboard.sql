CREATE OR REPLACE FUNCTION get_operational_alerts(p_workspace_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_result json;
BEGIN
    SELECT json_build_object(
        'pendingBudgets', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Analise Tecnica'
              AND t.budget_status IS NULL
              AND t.deleted_at IS NULL
        ),
        'waitingBudgetResponse', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Aprovacao'
              AND t.budget_status = 'Enviado'
              AND t.deleted_at IS NULL
        ),
        'pendingPickups', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Retirada Cliente'
              AND (t.pickup_available IS FALSE OR t.pickup_available IS NULL)
              AND t.deleted_at IS NULL
        ),
        'urgentAnalysis', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.analysis_deadline < now()
              AND t.status NOT IN ('Finalizado', 'Retirada Cliente')
              AND t.deleted_at IS NULL
        ),
        'delayedDeliveries', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.deadline < now()
              AND t.status NOT IN ('Finalizado', 'Retirada Cliente')
              AND t.deleted_at IS NULL
        ),
        'priorityTickets', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.priority_requested = true
              AND t.status <> 'Finalizado'
              AND t.deleted_at IS NULL
        ),
        'pendingPurchase', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Compra Peca'
              AND (t.parts_status IS NULL OR t.parts_status = 'Pendente')
              AND t.deleted_at IS NULL
        ),
        'pendingReceipt', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Compra Peca'
              AND t.parts_status = 'Comprado'
              AND t.deleted_at IS NULL
        ),
        'pendingTech', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Aberto'
              AND (t.is_outsourced IS FALSE OR t.is_outsourced IS NULL)
              AND t.deleted_at IS NULL
        ),
        'outsourcedToSend', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Aberto'
              AND t.is_outsourced = TRUE
              AND t.deleted_at IS NULL
        ),
        'pendingOutsourced', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Terceirizado'
              AND t.deleted_at IS NULL
        ),
        'pendingTracking', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Retirada Cliente'
              AND t.pickup_available = TRUE
              AND t.delivery_method = 'carrier'
              AND t.tracking_code IS NULL
              AND t.deleted_at IS NULL
        ),
        'pendingDelivery', (
            SELECT COALESCE(json_agg(t), '[]'::json)
            FROM tickets t
            WHERE t.workspace_id = p_workspace_id
              AND t.status = 'Retirada Cliente'
              AND t.pickup_available = TRUE
              AND (
                  (t.delivery_method = 'carrier' AND t.tracking_code IS NOT NULL) OR
                  (t.delivery_method = 'pickup')
              )
              AND t.deleted_at IS NULL
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;
