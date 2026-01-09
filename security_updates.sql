-- 1. Add WhatsApp Number to Workspaces
ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS whatsapp_number TEXT;

-- 2. Enable RLS on all tables
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_logs ENABLE ROW LEVEL SECURITY;

-- 3. Create Secure RPC for Client Tracking
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
    whatsapp_number TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_workspace_id UUID;
BEGIN
    SELECT workspace_id INTO v_workspace_id FROM public.tickets WHERE public.tickets.id = p_ticket_id;

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
        w.whatsapp_number
    FROM public.tickets t
    JOIN public.workspaces w ON w.id = t.workspace_id
    WHERE t.id = p_ticket_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_client_ticket_details(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details(UUID) TO service_role;

-- 4. RLS POLICIES (Drop first to avoid errors)

-- === WORKSPACES ===
DROP POLICY IF EXISTS "Admin view own workspace" ON public.workspaces;
CREATE POLICY "Admin view own workspace" ON public.workspaces
FOR ALL TO authenticated
USING (owner_id = auth.uid());

DROP POLICY IF EXISTS "Employee view own workspace" ON public.workspaces;
CREATE POLICY "Employee view own workspace" ON public.workspaces
FOR SELECT TO anon
USING (id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);


-- === TICKETS ===
DROP POLICY IF EXISTS "Admin access tickets" ON public.tickets;
CREATE POLICY "Admin access tickets" ON public.tickets
FOR ALL TO authenticated
USING (workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid()));

DROP POLICY IF EXISTS "Employee access tickets" ON public.tickets;
CREATE POLICY "Employee access tickets" ON public.tickets
FOR ALL TO anon
USING (workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);


-- === EMPLOYEES ===
DROP POLICY IF EXISTS "Admin manage employees" ON public.employees;
CREATE POLICY "Admin manage employees" ON public.employees
FOR ALL TO authenticated
USING (workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid()));

DROP POLICY IF EXISTS "Employee view colleagues" ON public.employees;
CREATE POLICY "Employee view colleagues" ON public.employees
FOR SELECT TO anon
USING (workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);


-- === CHECKLIST TEMPLATES ===
DROP POLICY IF EXISTS "Admin manage templates" ON public.checklist_templates;
CREATE POLICY "Admin manage templates" ON public.checklist_templates
FOR ALL TO authenticated
USING (workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid()));

DROP POLICY IF EXISTS "Employee use templates" ON public.checklist_templates;
CREATE POLICY "Employee use templates" ON public.checklist_templates
FOR ALL TO anon
USING (workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);


-- === NOTIFICATIONS ===
DROP POLICY IF EXISTS "Admin manage notifications" ON public.notifications;
CREATE POLICY "Admin manage notifications" ON public.notifications
FOR ALL TO authenticated
USING (true);

DROP POLICY IF EXISTS "Access notifications via ticket workspace" ON public.notifications;
CREATE POLICY "Access notifications via ticket workspace" ON public.notifications
FOR ALL TO anon
USING (
   EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
      AND t.workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
   )
);


-- === TICKET LOGS ===
DROP POLICY IF EXISTS "Admin view logs" ON public.ticket_logs;
CREATE POLICY "Admin view logs" ON public.ticket_logs
FOR ALL TO authenticated
USING (
   EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
      AND t.workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())
   )
);

DROP POLICY IF EXISTS "Employee view/create logs" ON public.ticket_logs;
CREATE POLICY "Employee view/create logs" ON public.ticket_logs
FOR ALL TO anon
USING (
   EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
      AND t.workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
   )
);

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT ALL ON TABLE public.tickets TO anon;
GRANT ALL ON TABLE public.checklist_templates TO anon;
GRANT ALL ON TABLE public.notifications TO anon;
GRANT ALL ON TABLE public.ticket_logs TO anon;
GRANT SELECT ON TABLE public.employees TO anon;
GRANT SELECT ON TABLE public.workspaces TO anon;
