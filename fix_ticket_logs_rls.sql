
-- Corrigir RLS para ticket_logs
ALTER TABLE public.ticket_logs ENABLE ROW LEVEL SECURITY;

-- Remover policies antigas que possam estar conflitantes
DROP POLICY IF EXISTS "Acesso Total Logs" ON public.ticket_logs;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON public.ticket_logs;
DROP POLICY IF EXISTS "Enable select for authenticated users" ON public.ticket_logs;

-- Criar política permissiva para usuários autenticados (Insert/Select/Update)
CREATE POLICY "Allow All for Authenticated"
ON public.ticket_logs
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- Garantir permissões de tabela
GRANT ALL ON TABLE public.ticket_logs TO authenticated;
GRANT ALL ON TABLE public.ticket_logs TO service_role;
