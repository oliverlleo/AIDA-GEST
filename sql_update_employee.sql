CREATE OR REPLACE FUNCTION public.update_employee(
    p_id uuid,
    p_name text,
    p_username text,
    p_password text,
    p_roles text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_workspace_id uuid;
BEGIN
    -- Verify target employee exists and get workspace_id
    SELECT e.workspace_id INTO v_workspace_id FROM employees e WHERE e.id = p_id;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Employee not found';
    END IF;

    -- Validate ownership / admin access using our helper
    IF NOT public.can_manage_workspace(v_workspace_id) THEN
         RAISE EXCEPTION 'Access denied';
    END IF;

    UPDATE employees
    SET
        name = p_name,
        username = p_username,
        password_hash = CASE
            WHEN p_password IS NOT NULL AND p_password <> ''
            THEN crypt(p_password, gen_salt('bf'))
            ELSE password_hash
        END,
        must_change_password = CASE
            WHEN p_password IS NOT NULL AND p_password <> '' THEN TRUE
            ELSE must_change_password
        END,
        roles = p_roles
    WHERE id = p_id;
END;
$function$;
