
-- ==============================================================================
-- STORAGE SECURITY HARDENING: REMOVE EMPLOYEE DIRECT WRITE ACCESS
-- ==============================================================================

-- 1. Drop the previous mixed policies (Secure Storage ...)
DROP POLICY IF EXISTS "Secure Storage Insert" ON storage.objects;
DROP POLICY IF EXISTS "Secure Storage Update" ON storage.objects;
DROP POLICY IF EXISTS "Secure Storage Delete" ON storage.objects;

-- 2. Re-create Admin-Only Policies (Ownership check)
-- This ensures Admins (authenticated via Supabase Auth) retain full access
-- provided they own the workspace folder.

-- INSERT (Admin Only)
CREATE POLICY "Admin Storage Insert" ON storage.objects
AS PERMISSIVE FOR INSERT TO authenticated
WITH CHECK (
    -- Path: workspace_id/...
    EXISTS (
        SELECT 1 FROM public.workspaces w
        WHERE w.id::text = (storage.foldername(name))[1]
          AND w.owner_id = auth.uid()
    )
);

-- UPDATE (Admin Only)
CREATE POLICY "Admin Storage Update" ON storage.objects
AS PERMISSIVE FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.workspaces w
        WHERE w.id::text = (storage.foldername(name))[1]
          AND w.owner_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.workspaces w
        WHERE w.id::text = (storage.foldername(name))[1]
          AND w.owner_id = auth.uid()
    )
);

-- DELETE (Admin Only)
CREATE POLICY "Admin Storage Delete" ON storage.objects
AS PERMISSIVE FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.workspaces w
        WHERE w.id::text = (storage.foldername(name))[1]
          AND w.owner_id = auth.uid()
    )
);

-- Note: SELECT policy ("Secure Storage Select") is kept or can be restricted.
-- Assuming SELECT might still need to work for viewing (Employees need to SEE photos).
-- If "Secure Storage Select" (created previously) covers employees via token, we KEEP it.
-- We only blocked WRITE operations.
