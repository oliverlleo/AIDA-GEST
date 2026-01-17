-- FIX RLS FINAL E ABSOLUTO (HEADER BASED)

ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

-- Limpar policies
DROP POLICY IF EXISTS "Isolation by Workspace Header" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Isolation by Workspace Robust" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Isolation by Workspace" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;

-- 1. Política para ADMINS (Autenticados via Supabase Auth)
CREATE POLICY "Admin All Access"
ON public.outsourced_companies
FOR ALL
TO authenticated
USING (
    workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())
)
WITH CHECK (
    workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())
);

-- 2. Política para FUNCIONÁRIOS (Anon via Header) - IGUAL A EMPLOYEES
CREATE POLICY "Employee Access via Header"
ON public.outsourced_companies
FOR ALL
TO anon
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
)
WITH CHECK (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

-- Permissões
GRANT ALL ON TABLE public.outsourced_companies TO anon, authenticated, service_role;
