-- FIX DEFINITIVO DE PERMISSÃO PARA FUNCIONÁRIOS (ANON)
-- O sistema usa login customizado que não preenche auth.uid(), dependendo do header x-workspace-id.

ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

-- Remove as políticas anteriores que exigiam auth.uid() (que funcionários não têm)
DROP POLICY IF EXISTS "Isolation by Workspace Robust" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Isolation by Workspace" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;

-- Cria política baseada EXCLUSIVAMENTE no cabeçalho x-workspace-id
-- Isso permite que funcionários (role anon) acessem os dados do seu workspace
CREATE POLICY "Isolation by Workspace Header"
ON public.outsourced_companies
FOR ALL
TO public -- Importante: 'public' abrange anon (funcionários) e authenticated (admin)
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
)
WITH CHECK (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

-- Garante que o role 'anon' (usado pelos funcionários) tenha permissão na tabela
GRANT ALL ON TABLE public.outsourced_companies TO anon, authenticated, service_role;
