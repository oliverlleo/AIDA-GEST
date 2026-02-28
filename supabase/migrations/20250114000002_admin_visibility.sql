BEGIN;

-- 1. DROP old function to allow return type change
DROP FUNCTION IF EXISTS public.get_employees_for_workspace(uuid);

-- 2. Update RPC to include lock status (Admin Only)
CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(p_workspace_id uuid)
 RETURNS TABLE(id uuid, name text, username text, roles text[], created_at timestamptz, workspace_id uuid, is_locked boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
BEGIN
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

-- 3. Create Trigger Function for Notifications
CREATE OR REPLACE FUNCTION public.handle_lockout_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
DECLARE
    v_emp_name text;
    v_workspace_id uuid;
BEGIN
    IF NEW.reset_required = true AND (OLD.reset_required = false OR OLD.reset_required IS NULL) THEN

        SELECT name, workspace_id INTO v_emp_name, v_workspace_id
        FROM public.employees
        WHERE id = NEW.employee_id;

        IF v_emp_name IS NOT NULL THEN
            INSERT INTO public.notifications (
                type,
                message,
                recipient_role,
                created_at
            ) VALUES (
                'security_alert',
                'BLOQUEIO: O usuário ' || v_emp_name || ' excedeu o limite de tentativas de login.',
                'admin',
                now()
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

-- 4. Attach Trigger
DROP TRIGGER IF EXISTS on_auth_state_lockout ON public.employee_auth_state;
CREATE TRIGGER on_auth_state_lockout
    AFTER UPDATE ON public.employee_auth_state
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_lockout_notification();

COMMIT;
