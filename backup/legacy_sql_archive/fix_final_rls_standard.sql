
-- 1. Remover policies antigas que podem estar causando conflito
DROP POLICY IF EXISTS "Workspace Isolation" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;

-- 2. Recriar a política padrão para funcionários (que já funciona em outras tabelas)
CREATE POLICY "Employee Access Standard"
ON public.outsourced_companies
FOR ALL
TO public
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
)
WITH CHECK (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

-- 3. Assegurar permissões
GRANT ALL ON TABLE public.outsourced_companies TO anon, authenticated;
