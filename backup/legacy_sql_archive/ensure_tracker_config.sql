
-- 1. Garantir que a coluna tracker_config existe
ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS tracker_config JSONB DEFAULT '{}'::JSONB;

-- 2. Garantir permissões de UPDATE para o Admin no próprio Workspace
-- Política: O dono (owner_id) pode atualizar seu workspace
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owner Update Workspace" ON public.workspaces;

CREATE POLICY "Owner Update Workspace"
ON public.workspaces
FOR UPDATE
USING (auth.uid() = owner_id)
WITH CHECK (auth.uid() = owner_id);

-- Garantir que Authenticated users podem ver (para login) e fazer update (se forem donos)
GRANT ALL ON TABLE public.workspaces TO authenticated;
