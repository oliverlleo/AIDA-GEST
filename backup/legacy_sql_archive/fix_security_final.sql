-- Fix Security: Remove conflicting permissive policies and enforce RLS

-- 1. Drop existing permissive policies
DROP POLICY IF EXISTS "Acesso Total Tickets" ON public.tickets;
DROP POLICY IF EXISTS "Acesso Total Templates" ON public.checklist_templates;
DROP POLICY IF EXISTS "Acesso Total Logs" ON public.ticket_logs;
DROP POLICY IF EXISTS "Leitura Publica Workspaces" ON public.workspaces;
DROP POLICY IF EXISTS "See own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Update notifications" ON public.notifications;
DROP POLICY IF EXISTS "Admins can view their workspace" ON public.workspaces;
DROP POLICY IF EXISTS "Authenticated users can insert workspace" ON public.workspaces;
DROP POLICY IF EXISTS "Admins can manage employees" ON public.employees;
DROP POLICY IF EXISTS "Permitir Insercao Logs" ON public.ticket_logs;
DROP POLICY IF EXISTS "Apenas Admin Ve Logs" ON public.ticket_logs;

-- 2. Force RLS on all tables
ALTER TABLE public.tickets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.workspaces FORCE ROW LEVEL SECURITY;
ALTER TABLE public.employees FORCE ROW LEVEL SECURITY;
ALTER TABLE public.checklist_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notifications FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_logs FORCE ROW LEVEL SECURITY;

-- 3. Ensure Strict Policies Exist (Use DO block to avoid 'already exists' errors or DROP/CREATE)
-- We will use DROP IF EXISTS then CREATE to be sure we have the latest definition.

-- === WORKSPACES ===
DROP POLICY IF EXISTS "Admin view own workspace" ON public.workspaces;
CREATE POLICY "Admin view own workspace" ON public.workspaces FOR ALL TO authenticated USING (owner_id = auth.uid());

DROP POLICY IF EXISTS "Employee view own workspace" ON public.workspaces;
CREATE POLICY "Employee view own workspace" ON public.workspaces FOR SELECT TO anon USING (id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);

-- === TICKETS ===
DROP POLICY IF EXISTS "Admin access tickets" ON public.tickets;
CREATE POLICY "Admin access tickets" ON public.tickets FOR ALL TO authenticated USING (workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid()));

DROP POLICY IF EXISTS "Employee access tickets" ON public.tickets;
CREATE POLICY "Employee access tickets" ON public.tickets FOR ALL TO anon USING (workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);

-- === EMPLOYEES ===
DROP POLICY IF EXISTS "Admin manage employees" ON public.employees;
CREATE POLICY "Admin manage employees" ON public.employees FOR ALL TO authenticated USING (workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid()));

DROP POLICY IF EXISTS "Employee view colleagues" ON public.employees;
CREATE POLICY "Employee view colleagues" ON public.employees FOR SELECT TO anon USING (workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);

-- === CHECKLIST TEMPLATES ===
DROP POLICY IF EXISTS "Admin manage templates" ON public.checklist_templates;
CREATE POLICY "Admin manage templates" ON public.checklist_templates FOR ALL TO authenticated USING (workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid()));

DROP POLICY IF EXISTS "Employee use templates" ON public.checklist_templates;
CREATE POLICY "Employee use templates" ON public.checklist_templates FOR ALL TO anon USING (workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid);

-- === NOTIFICATIONS ===
DROP POLICY IF EXISTS "Admin manage notifications" ON public.notifications;
CREATE POLICY "Admin manage notifications" ON public.notifications FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM public.tickets t JOIN public.workspaces w ON t.workspace_id = w.id WHERE t.id = ticket_id AND w.owner_id = auth.uid()));

DROP POLICY IF EXISTS "Access notifications via ticket workspace" ON public.notifications;
CREATE POLICY "Access notifications via ticket workspace" ON public.notifications FOR ALL TO anon USING (EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = ticket_id AND t.workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid));

-- === TICKET LOGS ===
DROP POLICY IF EXISTS "Admin view logs" ON public.ticket_logs;
CREATE POLICY "Admin view logs" ON public.ticket_logs FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = ticket_id AND t.workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())));

DROP POLICY IF EXISTS "Employee view/create logs" ON public.ticket_logs;
CREATE POLICY "Employee view/create logs" ON public.ticket_logs FOR ALL TO anon USING (EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = ticket_id AND t.workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid));
