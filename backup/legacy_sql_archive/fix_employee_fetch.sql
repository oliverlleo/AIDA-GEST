
-- Function to allow employees (who don't have auth.uid()) to fetch their colleagues
-- Security relies on knowing the workspace_id (which they get after successful login)
CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(
    p_workspace_id UUID
) RETURNS TABLE (
    id UUID,
    workspace_id UUID,
    name TEXT,
    username TEXT,
    roles TEXT[],
    created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT e.id, e.workspace_id, e.name, e.username, e.roles, e.created_at
    FROM public.employees e
    WHERE e.workspace_id = p_workspace_id
    ORDER BY e.created_at DESC;
END;
$$;
