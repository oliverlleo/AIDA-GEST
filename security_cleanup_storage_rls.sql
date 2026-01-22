-- ==============================================================================
-- CLEANUP & HARDENING: STORAGE RLS
-- Removes policies relying on insecure x-workspace-id header in STORAGE.
-- Enforces token-based access for employees and ownership for admins.
-- ==============================================================================

-- 1. DROP LEGACY POLICIES (Insecure Header Based)
DROP POLICY IF EXISTS "Allow Modify by Workspace" ON storage.objects;
DROP POLICY IF EXISTS "Allow Read by Workspace"   ON storage.objects;
DROP POLICY IF EXISTS "Allow Upload by Workspace" ON storage.objects;

-- 2. CREATE SECURE POLICIES
-- Target Buckets: ticket_photos, logo? (Assuming logic applies generally if path starts with workspace UUID)

-- SELECT (View)
CREATE POLICY "Secure Storage Select" ON storage.objects
AS PERMISSIVE FOR SELECT TO anon, authenticated
USING (
    bucket_id IN ('ticket_photos') AND
    (
        -- Path Structure: workspace_id/ticket_id/filename
        -- Extract Workspace ID: (storage.foldername(name))[1]

        -- Admin: Check Ownership
        (auth.role() = 'authenticated' AND EXISTS (
            SELECT 1 FROM public.workspaces w
            WHERE w.id::text = (storage.foldername(name))[1]
              AND w.owner_id = auth.uid()
        ))
        OR
        -- Employee: Check Token
        (
            -- Regex validation to prevent casting errors on bad paths
            (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            AND
            ((storage.foldername(name))[1])::uuid = (SELECT workspace_id FROM public.current_employee_from_token())
        )
    )
);

-- INSERT (Upload)
CREATE POLICY "Secure Storage Insert" ON storage.objects
AS PERMISSIVE FOR INSERT TO anon, authenticated
WITH CHECK (
    bucket_id IN ('ticket_photos') AND
    (
        -- Admin
        (auth.role() = 'authenticated' AND EXISTS (
            SELECT 1 FROM public.workspaces w
            WHERE w.id::text = (storage.foldername(name))[1]
              AND w.owner_id = auth.uid()
        ))
        OR
        -- Employee
        (
            (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            AND
            ((storage.foldername(name))[1])::uuid = (SELECT workspace_id FROM public.current_employee_from_token())
        )
    )
);

-- UPDATE (Modify) - Rarely used but good practice
CREATE POLICY "Secure Storage Update" ON storage.objects
AS PERMISSIVE FOR UPDATE TO anon, authenticated
USING (
    bucket_id IN ('ticket_photos') AND
    (
        (auth.role() = 'authenticated' AND EXISTS (
            SELECT 1 FROM public.workspaces w
            WHERE w.id::text = (storage.foldername(name))[1]
              AND w.owner_id = auth.uid()
        ))
        OR
        (
            (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            AND
            ((storage.foldername(name))[1])::uuid = (SELECT workspace_id FROM public.current_employee_from_token())
        )
    )
)
WITH CHECK (
    bucket_id IN ('ticket_photos') AND
    (
        (auth.role() = 'authenticated' AND EXISTS (
            SELECT 1 FROM public.workspaces w
            WHERE w.id::text = (storage.foldername(name))[1]
              AND w.owner_id = auth.uid()
        ))
        OR
        (
            (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            AND
            ((storage.foldername(name))[1])::uuid = (SELECT workspace_id FROM public.current_employee_from_token())
        )
    )
);

-- DELETE
CREATE POLICY "Secure Storage Delete" ON storage.objects
AS PERMISSIVE FOR DELETE TO anon, authenticated
USING (
    bucket_id IN ('ticket_photos') AND
    (
        (auth.role() = 'authenticated' AND EXISTS (
            SELECT 1 FROM public.workspaces w
            WHERE w.id::text = (storage.foldername(name))[1]
              AND w.owner_id = auth.uid()
        ))
        OR
        (
            (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            AND
            ((storage.foldername(name))[1])::uuid = (SELECT workspace_id FROM public.current_employee_from_token())
        )
    )
);
