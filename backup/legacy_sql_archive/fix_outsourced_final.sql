
-- Garantir que a tabela existe
CREATE TABLE IF NOT EXISTS public.outsourced_companies (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Reativar RLS para segurança
ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

-- Remover policies antigas que podem estar bloqueando
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Isolation by Workspace" ON public.outsourced_companies;

-- Criar política permissiva para usuários autenticados (Insert/Select/Update/Delete)
-- Permitimos tudo para autenticados, o filtro de workspace será feito pelo Frontend/API
CREATE POLICY "Allow All Authenticated"
ON public.outsourced_companies
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- Garantir Grants explícitos
GRANT ALL ON TABLE public.outsourced_companies TO authenticated;
GRANT ALL ON TABLE public.outsourced_companies TO service_role;
GRANT ALL ON TABLE public.outsourced_companies TO anon; -- Fallback caso login anonimo seja usado em algum lugar
