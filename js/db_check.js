
async function installDatabase() {
    const SUPABASE_URL = 'https://cpydazjwlmssbzzsurxu.supabase.co';
    const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNweWRhemp3bG1zc2J6enN1cnh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc4Mjg5MTUsImV4cCI6MjA4MzQwNDkxNX0.NM7cuB6mks74ZzfvMYhluIjnqBXVgtolHbN4huKmE-Q';

    // We try to call a standard RPC if available, or just inform the user
    // Since we can't run raw SQL from client without a specific RPC.

    console.log("Tentando verificar banco de dados...");

    // Check if tickets table exists
    const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    const { error } = await client.from('tickets').select('id').limit(1);

    if (error && error.code === 'PGRST205') {
        // Table missing
        const modalHtml = `
            <div id="install-modal" style="position:fixed;inset:0;background:rgba(0,0,0,0.9);z-index:9999;display:flex;align-items:center;justify-content:center;color:white;font-family:sans-serif;">
                <div style="background:#1a1a1a;padding:40px;border-radius:12px;max-width:600px;text-align:center;border:2px solid #FF6B00;">
                    <h1 style="color:#FF6B00;margin-bottom:20px;">Instalação Necessária</h1>
                    <p style="margin-bottom:20px;line-height:1.5;">O sistema detectou que o banco de dados ainda não foi configurado corretamente.</p>
                    <p style="margin-bottom:20px;font-size:14px;color:#aaa;">Copie o código abaixo e execute no SQL Editor do Supabase:</p>
                    <textarea readonly style="width:100%;height:150px;background:#333;color:#eee;border:none;padding:10px;margin-bottom:20px;border-radius:4px;font-family:monospace;">
-- EXECUTE NO SUPABASE SQL EDITOR --

CREATE TABLE IF NOT EXISTS public.tickets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    client_name TEXT NOT NULL,
    contact_info TEXT,
    os_number TEXT NOT NULL,
    entry_date TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    deadline TIMESTAMP WITH TIME ZONE,
    priority TEXT DEFAULT 'Normal',
    device_model TEXT NOT NULL,
    serial_number TEXT,
    defect_reported TEXT,
    device_condition TEXT,
    checklist_data JSONB DEFAULT '{}'::JSONB,
    photos_urls TEXT[] DEFAULT '{}',
    status TEXT DEFAULT 'Aberto',
    previous_status TEXT,
    tech_notes TEXT,
    parts_needed TEXT,
    parts_status TEXT DEFAULT 'N/A',
    parts_purchased_at TIMESTAMP WITH TIME ZONE,
    parts_received_at TIMESTAMP WITH TIME ZONE,
    budget_value DECIMAL(10,2),
    budget_status TEXT DEFAULT 'Pendente',
    budget_sent_at TIMESTAMP WITH TIME ZONE,
    repair_successful BOOLEAN,
    repair_start_at TIMESTAMP WITH TIME ZONE,
    repair_end_at TIMESTAMP WITH TIME ZONE,
    test_start_at TIMESTAMP WITH TIME ZONE,
    pickup_available BOOLEAN DEFAULT FALSE,
    pickup_available_at TIMESTAMP WITH TIME ZONE,
    created_by UUID,
    created_by_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ticket_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ticket_id UUID REFERENCES public.tickets(id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    details TEXT,
    user_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.checklist_templates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID,
    name TEXT NOT NULL,
    items JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

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

ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checklist_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Acesso Total Tickets" ON public.tickets;
CREATE POLICY "Acesso Total Tickets" ON public.tickets FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acesso Total Logs" ON public.ticket_logs;
CREATE POLICY "Acesso Total Logs" ON public.ticket_logs FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acesso Total Templates" ON public.checklist_templates;
CREATE POLICY "Acesso Total Templates" ON public.checklist_templates FOR ALL USING (true) WITH CHECK (true);

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tickets TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.ticket_logs TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.checklist_templates TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
                    </textarea>
                    <button onclick="document.getElementById('install-modal').remove()" style="background:#333;color:white;padding:10px 20px;border:none;border-radius:4px;cursor:pointer;">Fechar</button>
                </div>
            </div>
        `;
        document.body.insertAdjacentHTML('beforeend', modalHtml);
    }
}

// Run on load
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', installDatabase);
} else {
    installDatabase();
}
