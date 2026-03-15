-- Drop the policy first to recreate
DROP POLICY IF EXISTS fp_logos_anon_insert ON storage.objects;
DROP POLICY IF EXISTS fp_logos_anon_update ON storage.objects;
DROP POLICY IF EXISTS fp_logos_anon_delete ON storage.objects;

CREATE POLICY "fp_logos_anon_insert" ON "storage"."objects"
AS PERMISSIVE FOR INSERT
TO public
WITH CHECK (bucket_id = 'workspace_logos'::text AND public.can_manage_logo(name));

CREATE POLICY "fp_logos_anon_update" ON "storage"."objects"
AS PERMISSIVE FOR UPDATE
TO public
USING (bucket_id = 'workspace_logos'::text AND public.can_manage_logo(name))
WITH CHECK (bucket_id = 'workspace_logos'::text AND public.can_manage_logo(name));

CREATE POLICY "fp_logos_anon_delete" ON "storage"."objects"
AS PERMISSIVE FOR DELETE
TO public
USING (bucket_id = 'workspace_logos'::text AND public.can_manage_logo(name));
