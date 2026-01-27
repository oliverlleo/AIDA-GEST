
-- Melhorar permissão de UPDATE no Workspace
-- Permitir que qualquer usuário que tenha um perfil 'admin' vinculado ao workspace possa editá-lo.

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

-- Remover política anterior restrita ao owner
DROP POLICY IF EXISTS "Owner Update Workspace" ON public.workspaces;

-- Criar política baseada em perfil de admin
CREATE POLICY "Admin Update Workspace"
ON public.workspaces
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
        AND profiles.workspace_id = workspaces.id
        AND profiles.role = 'admin'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
        AND profiles.workspace_id = workspaces.id
        AND profiles.role = 'admin'
    )
);

-- Garantir Select também (caso não tenha)
DROP POLICY IF EXISTS "Admin Select Workspace" ON public.workspaces;
CREATE POLICY "Admin Select Workspace"
ON public.workspaces
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
        AND profiles.workspace_id = workspaces.id
    )
);
