CREATE OR REPLACE FUNCTION public.can_manage_logo(p_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_workspace_id text;
BEGIN
  -- Extract workspace_id from path (first segment)
  v_workspace_id := split_part(p_name, '/', 1);

  -- 1. Check if User is Owner (Supabase Auth)
  IF auth.role() = 'authenticated' AND EXISTS (
    SELECT 1 FROM public.workspaces
    WHERE id::text = v_workspace_id
    AND owner_id = auth.uid()
  ) THEN
    RETURN true;
  END IF;

  -- Check if user is an admin via profile
  IF auth.role() = 'authenticated' AND EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND workspace_id::text = v_workspace_id
    AND role = 'admin'
  ) THEN
    RETURN true;
  END IF;

  -- 2. Check if User is Employee Admin (via Token)
  IF EXISTS (
    SELECT 1 FROM public.current_employee_from_token() t
    WHERE t.workspace_id::text = v_workspace_id
    AND t.roles::text ILIKE '%admin%'
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$function$;
