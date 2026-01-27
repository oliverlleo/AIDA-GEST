-- 1) Create public_token column with secure defaults
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.tickets
ADD COLUMN IF NOT EXISTS public_token uuid DEFAULT gen_random_uuid();

-- 2) Backfill existing records (if any were created without default during a race condition, though default handles new ones)
UPDATE public.tickets
SET public_token = gen_random_uuid()
WHERE public_token IS NULL;

-- 3) Enforce constraints
ALTER TABLE public.tickets
ALTER COLUMN public_token SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS tickets_public_token_uq
ON public.tickets(public_token);

-- 4) Create New Secure RPC
CREATE OR REPLACE FUNCTION public.get_client_ticket_details_public(
  p_ticket_id uuid,
  p_public_token uuid
)
RETURNS TABLE(
  id uuid,
  os_number text,
  device_model text,
  status text,
  deadline timestamptz,
  priority_requested boolean,
  pickup_available boolean,
  created_at timestamptz,
  whatsapp_number text,
  tracker_config jsonb,
  delivery_method text,
  carrier_name text,
  tracking_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    AND t.deleted_at IS NULL;
END;
$$;

-- 5) Secure Permissions
-- Revoke insecure access
REVOKE EXECUTE ON FUNCTION public.get_client_ticket_details(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_client_ticket_details(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_client_ticket_details(uuid) FROM authenticated;

-- Grant secure access
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid, uuid) TO service_role;
