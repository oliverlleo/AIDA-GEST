
-- Desabilitar RLS na tabela de empresas terceirizadas para garantir visibilidade total
ALTER TABLE public.outsourced_companies DISABLE ROW LEVEL SECURITY;

-- Garantir permissões de acesso
GRANT ALL ON TABLE public.outsourced_companies TO anon, authenticated, service_role;

-- Remover qualquer política restritiva anterior se existir
DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;
