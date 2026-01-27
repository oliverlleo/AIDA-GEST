
-- Reativar RLS
ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

-- Remover policies antigas
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Isolation by Workspace" ON public.outsourced_companies;

-- Criar Política Segura Corrigida
-- O Supabase passa o header como texto, precisamos comparar com o UUID da tabela.
CREATE POLICY "Isolation by Workspace"
ON public.outsourced_companies
FOR ALL
USING (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
)
WITH CHECK (
    workspace_id = (current_setting('request.headers', true)::json->>'x-workspace-id')::uuid
);

-- Garantir Grants
GRANT ALL ON TABLE public.outsourced_companies TO authenticated;
