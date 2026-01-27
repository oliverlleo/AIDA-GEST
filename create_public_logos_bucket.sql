-- 1) Create the new public bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('workspace_logos', 'workspace_logos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2) Drop existing policies if any (cleanup)
DROP POLICY IF EXISTS "Logos Public Read" ON storage.objects;
DROP POLICY IF EXISTS "Logos Secure Upload" ON storage.objects;
DROP POLICY IF EXISTS "Logos Secure Update" ON storage.objects;
DROP POLICY IF EXISTS "Logos Secure Delete" ON storage.objects;

-- 3) Policy: Public Read Access
CREATE POLICY "Logos Public Read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'workspace_logos');

-- 4) Policy: Secure Upload (Insert)
-- Allowed if path starts with workspace_id AND (user is Owner OR user is Employee of that workspace)
CREATE POLICY "Logos Secure Upload"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (
  bucket_id = 'workspace_logos'
  AND (
    -- Option A: Authenticated Owner (Supabase Auth)
    (auth.role() = 'authenticated' AND EXISTS (
       SELECT 1 FROM public.workspaces w
       WHERE w.id::text = (storage.foldername(name))[1]
       AND w.owner_id = auth.uid()
    ))
    OR
    -- Option B: Authenticated Employee (Token)
    ((storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()))
  )
);

-- 5) Policy: Secure Update
CREATE POLICY "Logos Secure Update"
ON storage.objects FOR UPDATE
TO anon, authenticated
USING (
  bucket_id = 'workspace_logos'
  AND (
    (auth.role() = 'authenticated' AND EXISTS (
       SELECT 1 FROM public.workspaces w
       WHERE w.id::text = (storage.foldername(name))[1]
       AND w.owner_id = auth.uid()
    ))
    OR
    ((storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()))
  )
)
WITH CHECK (
  bucket_id = 'workspace_logos'
  AND (
    (auth.role() = 'authenticated' AND EXISTS (
       SELECT 1 FROM public.workspaces w
       WHERE w.id::text = (storage.foldername(name))[1]
       AND w.owner_id = auth.uid()
    ))
    OR
    ((storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()))
  )
);

-- 6) Policy: Secure Delete
CREATE POLICY "Logos Secure Delete"
ON storage.objects FOR DELETE
TO anon, authenticated
USING (
  bucket_id = 'workspace_logos'
  AND (
    (auth.role() = 'authenticated' AND EXISTS (
       SELECT 1 FROM public.workspaces w
       WHERE w.id::text = (storage.foldername(name))[1]
       AND w.owner_id = auth.uid()
    ))
    OR
    ((storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()))
  )
);
