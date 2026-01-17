
-- Criar Nova Tabela de Terceirizados
CREATE TABLE IF NOT EXISTS public.terceirizados (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- RLS e Permissões
ALTER TABLE public.terceirizados ENABLE ROW LEVEL SECURITY;

-- Remover policies antigas se existirem
DROP POLICY IF EXISTS "Acesso Total Terceirizados" ON public.terceirizados;

-- Criar política permissiva para usuários autenticados
CREATE POLICY "Acesso Total Terceirizados"
ON public.terceirizados
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- Garantir permissões
GRANT ALL ON TABLE public.terceirizados TO authenticated;
GRANT ALL ON TABLE public.terceirizados TO service_role;
