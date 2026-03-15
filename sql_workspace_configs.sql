CREATE OR REPLACE FUNCTION public.update_workspace_company_config(
    p_whatsapp_number text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_workspace_id UUID;
    v_user_id UUID;
BEGIN
    -- 1. Secure Workspace Resolution
    v_user_id := auth.uid();

    IF v_user_id IS NOT NULL THEN
        SELECT workspace_id INTO v_workspace_id
        FROM profiles
        WHERE id = v_user_id;

        IF v_workspace_id IS NULL THEN
            SELECT id INTO v_workspace_id
            FROM workspaces
            WHERE owner_id = v_user_id
            LIMIT 1;
        END IF;
    END IF;

    IF v_workspace_id IS NULL THEN
        SELECT t.workspace_id INTO v_workspace_id
        FROM public.current_employee_from_token() t
        WHERE t.roles::text ILIKE '%admin%'
        LIMIT 1;
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: Workspace não encontrado para o usuário ou permissão insuficiente.';
    END IF;

    -- Update only allowed fields
    UPDATE public.workspaces
    SET whatsapp_number = p_whatsapp_number
    WHERE id = v_workspace_id;

END;
$function$;

CREATE OR REPLACE FUNCTION public.update_workspace_tracker_config(
    p_config jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_workspace_id UUID;
    v_user_id UUID;
BEGIN
    -- 1. Secure Workspace Resolution
    v_user_id := auth.uid();

    IF v_user_id IS NOT NULL THEN
        SELECT workspace_id INTO v_workspace_id
        FROM profiles
        WHERE id = v_user_id;

        IF v_workspace_id IS NULL THEN
            SELECT id INTO v_workspace_id
            FROM workspaces
            WHERE owner_id = v_user_id
            LIMIT 1;
        END IF;
    END IF;

    IF v_workspace_id IS NULL THEN
        SELECT t.workspace_id INTO v_workspace_id
        FROM public.current_employee_from_token() t
        WHERE t.roles::text ILIKE '%admin%'
        LIMIT 1;
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: Workspace não encontrado para o usuário ou permissão insuficiente.';
    END IF;

    -- Update only allowed fields
    UPDATE public.workspaces
    SET tracker_config = p_config
    WHERE id = v_workspace_id;

END;
$function$;
