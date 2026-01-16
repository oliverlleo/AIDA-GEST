
-- Tabela de Empresas Terceirizadas
CREATE TABLE IF NOT EXISTS public.outsourced_companies (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Colunas de Controle no Ticket
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS is_outsourced BOOLEAN DEFAULT FALSE;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_company_id UUID REFERENCES public.outsourced_companies(id);
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_deadline TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_return_count INT DEFAULT 0;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_failure_reason TEXT;

-- RLS para outsourced_companies
ALTER TABLE public.outsourced_companies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Acesso Total Outsourced" ON public.outsourced_companies;
CREATE POLICY "Acesso Total Outsourced" ON public.outsourced_companies FOR ALL USING (true) WITH CHECK (true);

-- Permissões
GRANT ALL ON TABLE public.outsourced_companies TO anon, authenticated, service_role;
