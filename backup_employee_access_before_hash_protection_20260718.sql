-- BACKUP DE PERMISSOES - 2026-07-18
-- Projeto Supabase: cpydazjwlmssbzzsurxu
-- Escopo: public.employees
-- Estado do front correspondente:
--   branch: agent/configurable-workflow-features
--   commit: 9e4f517554e36040095097788fce8de00e996361
--   backup remoto: backup/pre-employee-password-hash-protection-20260718
--
-- Esta etapa nao altera dados nem hashes. Este arquivo restaura apenas as
-- permissoes que serao restringidas pela protecao de password_hash.

BEGIN;

-- Remove eventuais permissoes de coluna criadas pela nova protecao.
REVOKE SELECT (
    id,
    workspace_id,
    name,
    username,
    roles,
    created_at,
    deleted_at,
    must_change_password
) ON TABLE public.employees FROM anon, authenticated;

-- Estado original confirmado antes da alteracao.
GRANT SELECT ON TABLE public.employees TO anon, authenticated;

-- service_role ja possuia SELECT e nao e alterado pela nova protecao.

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Politicas RLS existentes no momento do backup (nao serao alteradas):
-- 1. "Admin manage employees": ALL para authenticated, limitado ao workspace
--    cujo owner_id corresponde a auth.uid().
-- 2. "Employees Access Policy": SELECT para anon/authenticated, limitado ao
--    workspace do owner ou ao workspace resolvido por current_employee_from_token().
