-- ==============================================================================
-- CLEANUP: FIX TERCEIRIZADOS (LEGACY/ALIAS)
-- Removes permissive 'USING (true)' policy
-- ==============================================================================

-- 1. DROP PERMISSIVE POLICY
DROP POLICY IF EXISTS "Acesso Total Terceirizados" ON public.terceirizados;

-- 2. CREATE SECURE POLICY (If table exists and is used)
-- Logic: Authenticated Users (Admins) only if they own the workspace related to the record.
-- Assuming terceirizados table has 'workspace_id'.
-- If not, we might need to inspect it. Assuming standard multi-tenant structure.

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'terceirizados') THEN
        ALTER TABLE public.terceirizados ENABLE ROW LEVEL SECURITY;

        -- Check if column workspace_id exists
        IF EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'terceirizados' AND column_name = 'workspace_id') THEN
             CREATE POLICY "Secure Access Terceirizados" ON public.terceirizados
             AS PERMISSIVE FOR ALL TO authenticated
             USING (
                 EXISTS (SELECT 1 FROM public.workspaces w
                         WHERE w.id = terceirizados.workspace_id
                           AND w.owner_id = auth.uid())
             )
             WITH CHECK (
                 EXISTS (SELECT 1 FROM public.workspaces w
                         WHERE w.id = terceirizados.workspace_id
                           AND w.owner_id = auth.uid())
             );
        ELSE
             -- Fallback: If no workspace_id, restrict to Auth owner only? Or just drop permissive.
             -- If it's a shared table without workspace isolation, it shouldn't exist in multi-tenant.
             -- Let's assume it has workspace_id based on project patterns.
             RAISE NOTICE 'Table terceirizados found but columns unknown. Policy dropped, no new policy created (Default Deny).';
        END IF;
    END IF;
END $$;
