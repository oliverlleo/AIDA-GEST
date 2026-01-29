
-- Fix dangerous RPCs with context validation

-- 1. get_employees_for_workspace
CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(p_workspace_id uuid)
 RETURNS TABLE(id uuid, workspace_id uuid, name text, username text, roles text[], created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
DECLARE
    v_ws_id uuid;
    v_user_id uuid;
BEGIN
    v_user_id := auth.uid();

    -- Case 1: Authenticated Admin
    IF auth.role() = 'authenticated' THEN
        -- Verify ownership
        IF NOT EXISTS (SELECT 1 FROM workspaces w WHERE w.id = p_workspace_id AND w.owner_id = v_user_id) THEN
             RAISE EXCEPTION 'Access denied';
        END IF;
        v_ws_id := p_workspace_id;

    -- Case 2: Anon Employee (with Token)
    ELSIF auth.role() = 'anon' THEN
        -- Derive from token
        SELECT x.workspace_id INTO v_ws_id FROM current_employee_from_token() x;
        IF v_ws_id IS NULL THEN
            RAISE EXCEPTION 'Invalid session';
        END IF;
    ELSE
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    RETURN QUERY
    SELECT e.id, e.workspace_id, e.name, e.username, e.roles, e.created_at
    FROM public.employees e
    WHERE e.workspace_id = v_ws_id
    AND e.deleted_at IS NULL
    ORDER BY e.created_at DESC;
END;
$function$;

-- 2. create_employee
CREATE OR REPLACE FUNCTION public.create_employee(p_workspace_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
DECLARE
    v_new_id UUID;
BEGIN
    -- Only authenticated admins
    IF auth.role() <> 'authenticated' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Verify ownership
    IF NOT EXISTS (SELECT 1 FROM workspaces w WHERE w.id = p_workspace_id AND w.owner_id = auth.uid()) THEN
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

-- 3. update_employee
CREATE OR REPLACE FUNCTION public.update_employee(p_id uuid, p_name text, p_username text, p_password text, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
DECLARE
    v_workspace_id uuid;
BEGIN
    -- Only authenticated admins
    IF auth.role() <> 'authenticated' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Verify target employee belongs to admin's workspace
    SELECT e.workspace_id INTO v_workspace_id FROM employees e WHERE e.id = p_id;

    IF NOT EXISTS (SELECT 1 FROM workspaces w WHERE w.id = v_workspace_id AND w.owner_id = auth.uid()) THEN
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
