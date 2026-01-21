
DROP FUNCTION IF EXISTS create_employee(uuid,text,text,text,text[]);

CREATE OR REPLACE FUNCTION create_employee(
    p_workspace_id UUID,
    p_name TEXT,
    p_username TEXT,
    p_password TEXT,
    p_roles TEXT[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_id UUID;
BEGIN
    INSERT INTO public.employees (workspace_id, name, username, password_hash, plain_password, roles)
    VALUES (p_workspace_id, p_name, p_username, crypt(p_password, gen_salt('bf')), p_password, p_roles)
    RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$$;
