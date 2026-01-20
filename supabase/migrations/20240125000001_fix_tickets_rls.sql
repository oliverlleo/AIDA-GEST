-- Fix Tickets RLS to be Workspace Isolated
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Acesso Total Tickets" ON public.tickets;
DROP POLICY IF EXISTS "Isolation by Workspace Header" ON public.tickets;
DROP POLICY IF EXISTS "Admin All Access" ON public.tickets;

-- 1. Admin Access (Authenticated)
CREATE POLICY "Admin All Access"
ON public.tickets
FOR ALL
TO authenticated
USING (
    workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())
)
WITH CHECK (
    workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())
);

-- 2. Employee Access (Anon via Header)
CREATE POLICY "Employee Access via Header"
ON public.tickets
FOR ALL
TO anon
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
)
WITH CHECK (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

GRANT ALL ON TABLE public.tickets TO anon, authenticated, service_role;
