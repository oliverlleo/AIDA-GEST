
-- Function to create workspace AND profile atomically
-- This ensures we never have a "half-created" admin account.
CREATE OR REPLACE FUNCTION public.create_owner_workspace_and_profile(
    p_name TEXT,
    p_company_code TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_workspace_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;

    -- 1. Insert Workspace
    INSERT INTO public.workspaces (name, company_code, owner_id)
    VALUES (p_name, p_company_code, auth.uid())
    RETURNING id INTO v_workspace_id;

    -- 2. Insert Profile (Admin Role)
    INSERT INTO public.profiles (id, workspace_id, role)
    VALUES (auth.uid(), v_workspace_id, 'admin');

    RETURN v_workspace_id;
END;
$$;
