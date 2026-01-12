
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

-- Policies (Security check via header, matching other tables in this custom auth setup)
DROP POLICY IF EXISTS "Access by Workspace Header" ON public.device_models;
DROP POLICY IF EXISTS "Acesso Total Modelos" ON public.device_models; -- Drop insecure policy if exists

CREATE POLICY "Access by Workspace Header" ON public.device_models
FOR ALL
TO anon, authenticated
USING (
    workspace_id::text = current_setting('request.headers', true)::json->>'x-workspace-id'
)
WITH CHECK (
    workspace_id::text = current_setting('request.headers', true)::json->>'x-workspace-id'
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_device_models_workspace ON public.device_models (workspace_id);
CREATE INDEX IF NOT EXISTS idx_device_models_name ON public.device_models (name);

-- Grant permissions
GRANT ALL ON TABLE public.device_models TO anon, authenticated, service_role;
