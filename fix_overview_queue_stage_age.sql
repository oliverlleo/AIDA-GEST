Exit code: 0
Wall time: 0.7 seconds
Output:
-- Stores the precise operational queue stage used by the Overview dashboard.
-- The timestamp only changes when a ticket actually moves to another queue stage.

ALTER TABLE public.tickets
    ADD COLUMN IF NOT EXISTS overview_queue_stage text,
    ADD COLUMN IF NOT EXISTS overview_queue_entered_at timestamptz;

CREATE OR REPLACE FUNCTION public.get_overview_queue_stage(ticket public.tickets)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_catalog
AS $$
    SELECT CASE
        WHEN ticket.is_outsourced
             AND ticket.status IN ('Aberto', 'Terceirizado')
             AND ticket.outsourced_at IS NULL
            THEN 'outsourced_to_send'
        WHEN ticket.is_outsourced
             AND ticket.status = 'Terceirizado'
             AND ticket.outsourced_at IS NOT NULL
            THEN 'outsourced_waiting_return'
        WHEN ticket.status = 'Retirada Cliente'
             AND NOT COALESCE(ticket.pickup_available, false)
            THEN 'pickup_pending'
        WHEN ticket.status = 'Retirada Cliente'
             AND COALESCE(ticket.pickup_available, false)
             AND ticket.delivery_method = 'carrier'
             AND NULLIF(btrim(COALESCE(ticket.tracking_code, '')), '') IS NULL
            THEN 'tracking_pending'
        WHEN ticket.status = 'Retirada Cliente'
             AND COALESCE(ticket.pickup_available, false)
            THEN 'delivery_pending'
        WHEN (ticket.status = 'Compra Peca'
              OR (ticket.status = 'Aprovacao'
                  AND NULLIF(btrim(COALESCE(ticket.parts_needed, '')), '') IS NOT NULL))
             AND ticket.parts_status = 'Comprado'
            THEN 'parts_receipt_pending'
        WHEN ticket.status = 'Compra Peca'
              OR (ticket.status = 'Aprovacao'
                  AND NULLIF(btrim(COALESCE(ticket.parts_needed, '')), '') IS NOT NULL)
            THEN 'parts_purchase_pending'
        WHEN ticket.status = 'Aprovacao'
             AND (ticket.budget_status = 'Enviado' OR ticket.budget_sent_at IS NOT NULL)
            THEN 'budget_approval_pending'
        WHEN ticket.status = 'Aprovacao'
            THEN 'budget_send_pending'
        WHEN ticket.status = 'Aberto' AND NOT COALESCE(ticket.is_outsourced, false)
            THEN 'analysis_start_pending'
        ELSE 'status:' || COALESCE(ticket.status, 'unknown')
    END;
$$;

UPDATE public.tickets t
SET overview_queue_stage = public.get_overview_queue_stage(t),
    overview_queue_entered_at = COALESCE(
        t.overview_queue_entered_at,
        CASE public.get_overview_queue_stage(t)
            WHEN 'budget_approval_pending' THEN t.budget_sent_at
            WHEN 'parts_receipt_pending' THEN t.parts_purchased_at
            WHEN 'tracking_pending' THEN t.pickup_available_at
            WHEN 'delivery_pending' THEN t.pickup_available_at
            WHEN 'outsourced_waiting_return' THEN t.outsourced_at
            ELSE NULL
        END,
        t.updated_at,
        t.created_at,
        t.entry_date,
        now()
    )
WHERE t.overview_queue_stage IS NULL
   OR t.overview_queue_entered_at IS NULL;

CREATE OR REPLACE FUNCTION public.set_overview_queue_stage()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_new_stage text;
BEGIN
    v_new_stage := public.get_overview_queue_stage(NEW);

    IF TG_OP = 'INSERT' THEN
        NEW.overview_queue_stage := v_new_stage;
        NEW.overview_queue_entered_at := COALESCE(NEW.overview_queue_entered_at, now());
    ELSIF NEW.overview_queue_stage IS DISTINCT FROM v_new_stage THEN
        NEW.overview_queue_stage := v_new_stage;
        NEW.overview_queue_entered_at := now();
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_overview_queue_stage ON public.tickets;
CREATE TRIGGER set_overview_queue_stage
BEFORE INSERT OR UPDATE OF
    status,
    budget_status,
    budget_sent_at,
    parts_needed,
    parts_status,
    parts_purchased_at,
    pickup_available,
    pickup_available_at,
    delivery_method,
    tracking_code,
    is_outsourced,
    outsourced_at
ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION public.set_overview_queue_stage();

ALTER TABLE public.tickets
    ALTER COLUMN overview_queue_stage SET NOT NULL,
    ALTER COLUMN overview_queue_entered_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS tickets_workspace_overview_queue_stage_idx
    ON public.tickets (workspace_id, overview_queue_stage, overview_queue_entered_at DESC)
    WHERE deleted_at IS NULL;

