
-- Garantir que a tabela existe (caso o db_install.sql não tenha sido rodado ou falhou)
CREATE TABLE IF NOT EXISTS public.ticket_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ticket_id UUID REFERENCES public.tickets(id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    details TEXT,
    user_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Permissões
ALTER TABLE public.ticket_logs ENABLE ROW LEVEL SECURITY;

-- Remove policies antigas para recriar
DROP POLICY IF EXISTS "Acesso Total Logs" ON public.ticket_logs;

-- Permitir tudo para simplificar (Anon/Auth) - A UI controlará a visibilidade
CREATE POLICY "Acesso Total Logs" ON public.ticket_logs FOR ALL USING (true) WITH CHECK (true);

-- Garantir Grants
GRANT ALL ON TABLE public.ticket_logs TO anon, authenticated, service_role;
