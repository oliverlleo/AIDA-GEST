
-- ==============================================================================
-- SCRIPT DE INSTALAÇÃO COMPLETA - TECHASSIST
-- ==============================================================================
-- Execute este script no SQL Editor do Supabase para criar todas as tabelas e permissões.

-- 1. Tabela de Tickets (Chamados)
CREATE TABLE IF NOT EXISTS public.tickets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL, -- Link com a empresa

    -- Dados Básicos
    client_name TEXT NOT NULL,
    contact_info TEXT,
    os_number TEXT NOT NULL,
    entry_date TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    deadline TIMESTAMP WITH TIME ZONE,
    priority TEXT DEFAULT 'Normal',

    -- Aparelho
    device_model TEXT NOT NULL,
    serial_number TEXT,
    defect_reported TEXT,
    device_condition TEXT,
    checklist_data JSONB DEFAULT '{}'::JSONB,
    photos_urls TEXT[] DEFAULT '{}',

    -- Fluxo e Status
    status TEXT DEFAULT 'Aberto',
    previous_status TEXT,

    -- Dados Técnicos
    tech_notes TEXT,
    parts_needed TEXT,
    parts_status TEXT DEFAULT 'N/A', -- N/A, Solicitado, Comprado, Recebido
    parts_purchased_at TIMESTAMP WITH TIME ZONE,
    parts_received_at TIMESTAMP WITH TIME ZONE,

    -- Financeiro
    budget_value DECIMAL(10,2),
    budget_status TEXT DEFAULT 'Pendente', -- Pendente, Enviado, Aprovado, Negado
    budget_sent_at TIMESTAMP WITH TIME ZONE,

    -- Reparo
    repair_successful BOOLEAN,
    repair_start_at TIMESTAMP WITH TIME ZONE,
    repair_end_at TIMESTAMP WITH TIME ZONE,

    -- Testes
    test_start_at TIMESTAMP WITH TIME ZONE,

    -- Retirada
    pickup_available BOOLEAN DEFAULT FALSE,
    pickup_available_at TIMESTAMP WITH TIME ZONE,

    -- Auditoria
    created_by UUID,
    created_by_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Tabela de Logs (Histórico)
CREATE TABLE IF NOT EXISTS public.ticket_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ticket_id UUID REFERENCES public.tickets(id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    details TEXT,
    user_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Tabela de Modelos de Checklist
CREATE TABLE IF NOT EXISTS public.checklist_templates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID,
    name TEXT NOT NULL,
    items JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ==============================================================================
-- TRIGGER PARA LOGS AUTOMÁTICOS
-- ==============================================================================
CREATE OR REPLACE FUNCTION log_ticket_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.status <> OLD.status THEN
            INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
            VALUES (NEW.id, 'Alteração de Status', 'De ' || OLD.status || ' para ' || NEW.status, 'Sistema');
        END IF;
    ELSIF (TG_OP = 'INSERT') THEN
         INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
         VALUES (NEW.id, 'Criado', 'Chamado aberto', NEW.created_by_name);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_ticket_change ON public.tickets;
CREATE TRIGGER on_ticket_change
    AFTER INSERT OR UPDATE ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION log_ticket_changes();

-- ==============================================================================
-- PERMISSÕES E SEGURANÇA (RLS)
-- ==============================================================================

-- Habilitar RLS
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checklist_templates ENABLE ROW LEVEL SECURITY;

-- Policies Permissivas (Necessário para o login customizado "Employee" que usa chave anon)
-- Se você quiser restringir, precisará de logica complexa no Policy verificando workspace_id
-- Porem, para garantir que funcione AGORA sem erros de permissão:

-- TICKETS
DROP POLICY IF EXISTS "Acesso Total Tickets" ON public.tickets;
CREATE POLICY "Acesso Total Tickets" ON public.tickets FOR ALL USING (true) WITH CHECK (true);

-- LOGS
DROP POLICY IF EXISTS "Acesso Total Logs" ON public.ticket_logs;
CREATE POLICY "Acesso Total Logs" ON public.ticket_logs FOR ALL USING (true) WITH CHECK (true);

-- TEMPLATES
DROP POLICY IF EXISTS "Acesso Total Templates" ON public.checklist_templates;
CREATE POLICY "Acesso Total Templates" ON public.checklist_templates FOR ALL USING (true) WITH CHECK (true);

-- CRITICAL: GRANT PERMISSIONS TO ROLES
-- Isso resolve o erro PGRST205 (Schema Cache) e 403 (Forbidden)
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tickets TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.ticket_logs TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.checklist_templates TO anon, authenticated, service_role;

-- Grant em sequencias caso existam (boas praticas)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
