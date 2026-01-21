
-- 1. Add tracker_config to Workspaces
ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS tracker_config JSONB DEFAULT '{}'::JSONB;

-- 2. Update RPC to return tracker_config
-- We drop first to allow changing the RETURN TABLE signature
DROP FUNCTION IF EXISTS public.get_client_ticket_details(UUID);

CREATE OR REPLACE FUNCTION public.get_client_ticket_details(p_ticket_id UUID)
RETURNS TABLE (
    id UUID,
    os_number TEXT,
    device_model TEXT,
    status TEXT,
    deadline TIMESTAMP WITH TIME ZONE,
    priority_requested BOOLEAN,
    pickup_available BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE,
    whatsapp_number TEXT,
    tracker_config JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
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
        w.tracker_config
    FROM public.tickets t
    JOIN public.workspaces w ON w.id = t.workspace_id
    WHERE t.id = p_ticket_id;
END;
$$;

-- 3. Grants
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details(UUID) TO service_role;
