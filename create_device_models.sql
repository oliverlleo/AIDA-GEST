
-- Tabela para modelos de dispositivos
CREATE TABLE IF NOT EXISTS public.device_models (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(workspace_id, name)
);

-- RLS
ALTER TABLE public.device_models ENABLE ROW LEVEL SECURITY;

-- Policies (Permissivas por enquanto para compatibilidade com sistema atual de login)
-- Idealmente seria checar workspace_id via header ou auth.uid
DROP POLICY IF EXISTS "Acesso Total Modelos" ON public.device_models;
CREATE POLICY "Acesso Total Modelos" ON public.device_models FOR ALL USING (true) WITH CHECK (true);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_device_models_workspace ON public.device_models (workspace_id);
CREATE INDEX IF NOT EXISTS idx_device_models_name ON public.device_models (name);

-- Grant permissions
GRANT ALL ON TABLE public.device_models TO anon, authenticated, service_role;
