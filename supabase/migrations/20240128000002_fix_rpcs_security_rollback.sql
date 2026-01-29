
-- Rollback: Restore original unsafe RPCs

CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(p_workspace_id uuid)
 RETURNS TABLE(id uuid, workspace_id uuid, name text, username text, roles text[], created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    RETURN QUERY
    SELECT e.id, e.workspace_id, e.name, e.username, e.roles, e.created_at
    FROM public.employees e
    WHERE e.workspace_id = p_workspace_id
    AND e.deleted_at IS NULL
    ORDER BY e.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_employee(p_workspace_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_new_id UUID;
BEGIN
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

CREATE OR REPLACE FUNCTION public.update_employee(p_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
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
