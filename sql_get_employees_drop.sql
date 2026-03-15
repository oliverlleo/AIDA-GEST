DROP FUNCTION IF EXISTS public.get_employees_for_workspace(uuid);

CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(
    p_workspace_id uuid
) RETURNS TABLE(
    id uuid,
    name text,
    username text,
    roles jsonb,
    created_at timestamp with time zone,
    workspace_id uuid,
    is_locked boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    -- Validate ownership / admin access using our helper
    IF NOT public.can_manage_workspace(p_workspace_id) THEN
        -- Return empty result securely
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        e.id,
        e.name,
        e.username,
        e.roles,
        e.created_at,
        e.workspace_id,
        COALESCE(s.reset_required, false) as is_locked
    FROM public.employees e
    LEFT JOIN public.employee_auth_state s ON e.id = s.employee_id
    WHERE e.workspace_id = p_workspace_id
    AND e.deleted_at IS NULL
    ORDER BY e.created_at DESC;
END;
$function$;
