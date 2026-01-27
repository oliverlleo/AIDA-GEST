-- CORREÇÃO ROBUSTA DA REGRA DE SEGURANÇA (RLS)
-- Substitui a verificação por cabeçalho (instável) por verificação de perfil (robusta)

ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

-- Remove políticas anteriores que podem estar falhando
DROP POLICY IF EXISTS "Isolation by Workspace" ON public.outsourced_companies;
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;

-- Cria política baseada no perfil do usuário autenticado (Padrão Supabase)
CREATE POLICY "Isolation by Workspace Robust"
ON public.outsourced_companies
FOR ALL
USING (
    workspace_id IN (
        SELECT workspace_id FROM public.profiles WHERE id = auth.uid()
    )
)
WITH CHECK (
    workspace_id IN (
        SELECT workspace_id FROM public.profiles WHERE id = auth.uid()
    )
);

-- Permissões básicas
GRANT ALL ON TABLE public.outsourced_companies TO authenticated;
