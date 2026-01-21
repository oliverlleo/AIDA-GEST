-- REVERTER AÇÃO INSEGURA E APLICAR CORREÇÃO RLS CORRETA

-- 1. Reativar RLS imediatamente
ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

-- 2. Remover policies antigas/permissivas
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;

-- 3. Criar Política Segura baseada no Workspace (Igual às outras tabelas)
-- Permite ver/editar apenas se o workspace_id bater com o cabeçalho da requisição
CREATE POLICY "Enable all for users based on workspace_id"
ON public.outsourced_companies
FOR ALL
USING (
    workspace_id = current_setting('request.headers')::json->>'x-workspace-id'::uuid
    OR
    (select auth.uid()) IS NOT NULL -- Fallback para permissão básica de leitura se necessário, mas o workspace deve bater.
)
WITH CHECK (
    workspace_id = current_setting('request.headers')::json->>'x-workspace-id'::uuid
);

-- Reforço: Política de leitura simples para garantir que o SELECT funcione na validação da FK
CREATE POLICY "Enable select for authenticated users"
ON public.outsourced_companies
FOR SELECT
TO authenticated
USING (true); -- Leitura liberada para autenticados (necessário para validação de FK em alguns casos), mas escrita restrita acima.
-- Se preferir estrito: USING (workspace_id = ...)

-- Vamos usar a abordagem padrão do projeto:
DROP POLICY IF EXISTS "Enable all for users based on workspace_id" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Enable select for authenticated users" ON public.outsourced_companies;

CREATE POLICY "Isolation by Workspace"
ON public.outsourced_companies
FOR ALL
USING (
    workspace_id::text = current_setting('request.headers', true)::json->>'x-workspace-id'
)
WITH CHECK (
    workspace_id::text = current_setting('request.headers', true)::json->>'x-workspace-id'
);

-- Garantir Grants
GRANT ALL ON TABLE public.outsourced_companies TO authenticated;
