-- Function to centralize logo permission logic securely
CREATE OR REPLACE FUNCTION public.can_manage_logo(p_name text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_workspace_id text;
BEGIN
  -- Extract workspace_id from path (first segment)
  -- Assumes path is "workspaceId/..."
  v_workspace_id := split_part(p_name, '/', 1);

  -- 1. Check if User is Owner (Supabase Auth)
  IF auth.role() = 'authenticated' AND EXISTS (
    SELECT 1 FROM public.workspaces
    WHERE id::text = v_workspace_id
    AND owner_id = auth.uid()
  ) THEN
    RETURN true;
  END IF;

  -- 2. Check if User is Employee (via Token)
  -- current_employee_from_token() returns TABLE(employee_id, workspace_id, role)
  -- We just need to check if the workspace_id matches.
  IF EXISTS (
    SELECT 1 FROM public.current_employee_from_token() t
    WHERE t.workspace_id::text = v_workspace_id
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- Grant execution to everyone (policies need it)
GRANT EXECUTE ON FUNCTION public.can_manage_logo(text) TO public;
GRANT EXECUTE ON FUNCTION public.can_manage_logo(text) TO anon;
GRANT EXECUTE ON FUNCTION public.can_manage_logo(text) TO authenticated;

-- Re-create Policies using the secure function
DROP POLICY IF EXISTS "Logos Secure Upload" ON storage.objects;
DROP POLICY IF EXISTS "Logos Secure Update" ON storage.objects;
DROP POLICY IF EXISTS "Logos Secure Delete" ON storage.objects;

CREATE POLICY "Logos Secure Upload"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (
  bucket_id = 'workspace_logos'
  AND public.can_manage_logo(name)
);

CREATE POLICY "Logos Secure Update"
ON storage.objects FOR UPDATE
TO anon, authenticated
USING (
  bucket_id = 'workspace_logos'
  AND public.can_manage_logo(name)
)
WITH CHECK (
  bucket_id = 'workspace_logos'
  AND public.can_manage_logo(name)
);

CREATE POLICY "Logos Secure Delete"
ON storage.objects FOR DELETE
TO anon, authenticated
USING (
  bucket_id = 'workspace_logos'
  AND public.can_manage_logo(name)
);
