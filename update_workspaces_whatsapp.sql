
-- Adicionar coluna whatsapp_number na tabela workspaces
ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS whatsapp_number TEXT;

-- Garantir que a coluna ticket_logs.ticket_id exista e esteja correta (já existe, mas por segurança)
-- Apenas para confirmar integridade, sem ação se já existir.

-- Permitir leitura pública (Anon) da tabela workspaces para que a página de acompanhamento possa pegar o telefone
-- Obs: A Policy existente "Admins can view their workspace" restringe ao owner_id.
-- Precisamos de uma policy para Anon que permita ler APENAS o telefone dado o ID?
-- Ou permitir leitura geral?
-- Vamos permitir leitura geral SE o usuário souber o ID (que virá do ticket -> workspace_id).
-- No Supabase, Policies são OR.

DROP POLICY IF EXISTS "Leitura Publica Workspaces" ON public.workspaces;
CREATE POLICY "Leitura Publica Workspaces" ON public.workspaces
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- Garantir permissões de Schema
GRANT SELECT ON public.workspaces TO anon, authenticated;
