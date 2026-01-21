CREATE OR REPLACE FUNCTION public.create_employee(
    p_workspace_id UUID,
    p_name TEXT,
    p_username TEXT,
    p_password TEXT,
    p_roles TEXT[]
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Check if executing user is admin of the workspace
    IF NOT EXISTS (
        SELECT 1 FROM public.workspaces
        WHERE id = p_workspace_id AND owner_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Access Denied';
    END IF;

    INSERT INTO public.employees (workspace_id, name, username, password_hash, roles)
    VALUES (
        p_workspace_id,
        p_name,
        p_username,
        crypt(p_password, gen_salt('bf')),
        p_roles
    );
END;
$$;
