CREATE OR REPLACE FUNCTION public.create_employee(
    p_workspace_id uuid,
    p_name text,
    p_username text,
    p_password text,
    p_roles text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_new_id UUID;
BEGIN
    -- Validate ownership / admin access using our helper
    IF NOT public.can_manage_workspace(p_workspace_id) THEN
         RAISE EXCEPTION 'Access denied';
    END IF;

    INSERT INTO public.employees (workspace_id, name, username, password_hash, roles, must_change_password)
    VALUES (
        p_workspace_id,
        p_name,
        p_username,
        crypt(p_password, gen_salt('bf')),
        p_roles,
        TRUE
    )
    RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$function$;
