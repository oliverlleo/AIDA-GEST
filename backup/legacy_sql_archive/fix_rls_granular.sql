-- FIX RLS GRANULAR (Separar Select de Modificação)

ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

-- Limpar policies anteriores
DROP POLICY IF EXISTS "Admin All Access" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Employee Access via Header" ON public.outsourced_companies;

-- 1. ADMIN (Authenticated) - Mantém acesso total baseado no owner
CREATE POLICY "Admin Full Access"
ON public.outsourced_companies
FOR ALL
TO authenticated
USING (
    workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())
)
WITH CHECK (
    workspace_id IN (SELECT id FROM public.workspaces WHERE owner_id = auth.uid())
);

-- 2. EMPLOYEE - SELECT (Anon) - IDÊNTICO à tabela employees
CREATE POLICY "Employee Select"
ON public.outsourced_companies
FOR SELECT
TO anon
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

-- 3. EMPLOYEE - MODIFICATION (Anon) - Inserir/Editar
CREATE POLICY "Employee Modification"
ON public.outsourced_companies
FOR INSERT
TO anon
WITH CHECK (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

CREATE POLICY "Employee Update"
ON public.outsourced_companies
FOR UPDATE
TO anon
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
)
WITH CHECK (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

CREATE POLICY "Employee Delete"
ON public.outsourced_companies
FOR DELETE
TO anon
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

-- Garantir Permissões
GRANT ALL ON TABLE public.outsourced_companies TO anon, authenticated, service_role;
