
-- Tabela para defeitos relatados
CREATE TABLE IF NOT EXISTS public.defect_options (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(workspace_id, name)
);

-- RLS
ALTER TABLE public.defect_options ENABLE ROW LEVEL SECURITY;

-- Policies (Security check via header, matching other tables in this custom auth setup)
DROP POLICY IF EXISTS "Access by Workspace Header" ON public.defect_options;
DROP POLICY IF EXISTS "Acesso Total Defeitos" ON public.defect_options; -- Drop insecure policy if exists

CREATE POLICY "Access by Workspace Header" ON public.defect_options
FOR ALL
TO anon, authenticated
USING (
    workspace_id::text = current_setting('request.headers', true)::json->>'x-workspace-id'
)
WITH CHECK (
    workspace_id::text = current_setting('request.headers', true)::json->>'x-workspace-id'
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_defect_options_workspace ON public.defect_options (workspace_id);
CREATE INDEX IF NOT EXISTS idx_defect_options_name ON public.defect_options (name);

-- Grant permissions
GRANT ALL ON TABLE public.defect_options TO anon, authenticated, service_role;
