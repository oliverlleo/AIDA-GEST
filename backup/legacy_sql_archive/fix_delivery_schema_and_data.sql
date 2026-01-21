
-- 1. Add the missing column 'delivered_at' safely
ALTER TABLE public.tickets
ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE;

-- 2. Force schema cache reload to ensure API sees the new column immediately
NOTIFY pgrst, 'reload config';

-- 3. Backfill Data Strategy

-- Step 3a: Backfill from Ticket Logs (Most Accurate)
-- We look for the exact moment the 'Finalizou Entrega' action happened.
UPDATE public.tickets t
SET delivered_at = subquery.log_date
FROM (
    SELECT ticket_id, MAX(created_at) as log_date
    FROM public.ticket_logs
    WHERE action = 'Finalizou Entrega'
    GROUP BY ticket_id
) AS subquery
WHERE t.id = subquery.ticket_id
  AND t.status = 'Finalizado'
  AND t.delivered_at IS NULL;

-- Step 3b: Backfill remaining finalized tickets using updated_at (Fallback)
-- For tickets that might have been finalized before logging was strict or if log is missing
UPDATE public.tickets
SET delivered_at = updated_at
WHERE status = 'Finalizado'
  AND delivered_at IS NULL;

-- 4. Verify (Optional Select to see impact, output will be shown in logs)
SELECT count(*) as fixed_tickets FROM public.tickets WHERE delivered_at IS NOT NULL;
