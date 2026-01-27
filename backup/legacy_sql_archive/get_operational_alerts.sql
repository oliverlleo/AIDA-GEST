CREATE OR REPLACE FUNCTION get_operational_alerts(p_workspace_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pending_budgets JSONB;
    v_waiting_budget_response JSONB;
    v_pending_pickups JSONB;
    v_urgent_analysis JSONB;
    v_delayed_deliveries JSONB;
    v_priority_tickets JSONB;
    v_pending_purchase JSONB;
    v_pending_receipt JSONB;
    v_pending_tech JSONB;
    v_pending_tracking JSONB;
    v_pending_delivery JSONB;
    v_pending_outsourced JSONB;
BEGIN
    -- Security Check: Ensure user belongs to workspace
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND workspace_id = p_workspace_id
    ) THEN
        RAISE EXCEPTION 'Access Denied';
    END IF;

    -- 1. Pending Budgets
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_pending_budgets
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Aprovacao'
      AND (t.budget_status IS NULL OR t.budget_status != 'Enviado');

    -- 2. Waiting Budget Response
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_waiting_budget_response
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Aprovacao'
      AND t.budget_status = 'Enviado';

    -- 3. Pending Pickups
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_pending_pickups
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Retirada Cliente'
      AND (t.pickup_available IS NULL OR t.pickup_available = FALSE);

    -- 4. Urgent Analysis (Limit 5)
    SELECT COALESCE(jsonb_agg(sub.*), '[]'::jsonb)
    INTO v_urgent_analysis
    FROM (
        SELECT * FROM tickets t
        WHERE t.workspace_id = p_workspace_id
          AND t.deleted_at IS NULL
          AND t.status = 'Analise Tecnica'
          AND t.analysis_deadline IS NOT NULL
        ORDER BY t.analysis_deadline ASC
        LIMIT 5
    ) sub;

    -- 5. Delayed Deliveries
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_delayed_deliveries
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.deadline < NOW()
      AND t.status NOT IN ('Retirada Cliente', 'Finalizado');

    -- 6. Priority Tickets
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_priority_tickets
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.priority_requested = TRUE
      AND t.status NOT IN ('Retirada Cliente', 'Finalizado');

    -- 7. Pending Purchase
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_pending_purchase
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Compra Peca'
      AND (t.parts_status IS NULL OR t.parts_status != 'Comprado');

    -- 8. Pending Receipt
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_pending_receipt
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Compra Peca'
      AND t.parts_status = 'Comprado';

    -- 9. Pending Tech (Aberto)
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_pending_tech
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Aberto';

    -- 10. Pending Tracking
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_pending_tracking
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Retirada Cliente'
      AND t.delivery_method = 'carrier'
      AND t.tracking_code IS NULL;

    -- 11. Pending Delivery (Liberado)
    SELECT COALESCE(jsonb_agg(t.*), '[]'::jsonb)
    INTO v_pending_delivery
    FROM tickets t
    WHERE t.workspace_id = p_workspace_id
      AND t.deleted_at IS NULL
      AND t.status = 'Retirada Cliente'
      AND (
          (t.delivery_method = 'pickup' AND t.pickup_available = TRUE)
          OR
          (t.delivery_method = 'carrier' AND t.tracking_code IS NOT NULL)
      );

    -- 12. Pending Outsourced
    SELECT COALESCE(jsonb_agg(sub.*), '[]'::jsonb)
    INTO v_pending_outsourced
    FROM (
        SELECT * FROM tickets t
        WHERE t.workspace_id = p_workspace_id
          AND t.deleted_at IS NULL
          AND t.status = 'Terceirizado'
        ORDER BY t.outsourced_deadline ASC
    ) sub;

    RETURN jsonb_build_object(
        'pendingBudgets', v_pending_budgets,
        'waitingBudgetResponse', v_waiting_budget_response,
        'pendingPickups', v_pending_pickups,
        'urgentAnalysis', v_urgent_analysis,
        'delayedDeliveries', v_delayed_deliveries,
        'priorityTickets', v_priority_tickets,
        'pendingPurchase', v_pending_purchase,
        'pendingReceipt', v_pending_receipt,
        'pendingTech', v_pending_tech,
        'pendingTracking', v_pending_tracking,
        'pendingDelivery', v_pending_delivery,
        'pendingOutsourced', v_pending_outsourced
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_operational_alerts(UUID) TO anon, authenticated, service_role;
