
-- Function to create workspace securely, bypassing RLS restrictions for the owner
CREATE OR REPLACE FUNCTION public.create_owner_workspace(
    p_name TEXT,
    p_company_code TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with privileges of the creator (postgres/admin)
AS $$
DECLARE
    v_workspace_id UUID;
BEGIN
    -- Insert workspace setting the owner to the current authenticated user
    -- auth.uid() comes from the JWT.
    -- If no user is logged in, this should fail or be blocked by API Gateway,
    -- but here we assume auth.uid() is valid if called by authenticated client.

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;

    INSERT INTO public.workspaces (name, company_code, owner_id)
    VALUES (p_name, p_company_code, auth.uid())
    RETURNING id INTO v_workspace_id;

    RETURN v_workspace_id;
END;
$$;
