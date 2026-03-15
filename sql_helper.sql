CREATE OR REPLACE FUNCTION public.can_manage_workspace(p_workspace_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id uuid;
    v_role text;
BEGIN
    -- 1. Check if authenticated user is the owner or an admin via profiles
    v_user_id := auth.uid();
    IF v_user_id IS NOT NULL THEN
        -- Check if owner in workspaces
        IF EXISTS (SELECT 1 FROM public.workspaces WHERE id = p_workspace_id AND owner_id = v_user_id) THEN
            RETURN true;
        END IF;

        -- Check if admin in profiles
        IF EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id AND workspace_id = p_workspace_id AND role = 'admin') THEN
            RETURN true;
        END IF;
    END IF;

    -- 2. Check employee session token
    IF EXISTS (
        SELECT 1
        FROM public.current_employee_from_token() t
        WHERE t.workspace_id = p_workspace_id
        AND t.roles::text ILIKE '%admin%'
    ) THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$function$;
