-- Keeps activity authors tied to the authenticated actor and applies the
-- same highlighted OS/client/device pattern to automatic history entries.

CREATE OR REPLACE FUNCTION public.get_current_actor_context()
RETURNS TABLE(
    workspace_id uuid,
    actor_user_id uuid,
    actor_employee_id uuid,
    actor_name text,
    actor_roles text[],
    actor_kind text,
    is_admin boolean,
    is_technician boolean,
    is_attendant boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_uid uuid;
    v_emp_id uuid;
    v_ws_id uuid;
    v_roles text[];
    v_name text;
    v_prof_ws uuid;
    v_prof_role text;
BEGIN
    v_uid := auth.uid();

    -- Metadata is used only as a display label for the currently authenticated
    -- user; authorization continues to depend on workspace/profile/token data.
    IF v_uid IS NOT NULL THEN
        SELECT id INTO v_ws_id
        FROM public.workspaces
        WHERE owner_id = v_uid
        LIMIT 1;

        IF v_ws_id IS NOT NULL THEN
            SELECT COALESCE(
                NULLIF(btrim(raw_user_meta_data ->> 'full_name'), ''),
                NULLIF(btrim(raw_user_meta_data ->> 'name'), '')
            )
            INTO v_name
            FROM auth.users
            WHERE id = v_uid;

            RETURN QUERY
            SELECT v_ws_id, v_uid, NULL::uuid, COALESCE(v_name, 'Administrador')::text,
                   ARRAY['admin']::text[], 'user'::text, true, false, false;
            RETURN;
        END IF;

        SELECT p.workspace_id, p.role
        INTO v_prof_ws, v_prof_role
        FROM public.profiles AS p
        WHERE p.id = v_uid
        LIMIT 1;

        IF v_prof_ws IS NOT NULL THEN
            SELECT COALESCE(
                NULLIF(btrim(raw_user_meta_data ->> 'full_name'), ''),
                NULLIF(btrim(raw_user_meta_data ->> 'name'), '')
            )
            INTO v_name
            FROM auth.users
            WHERE id = v_uid;

            RETURN QUERY
            SELECT v_prof_ws, v_uid, NULL::uuid, COALESCE(v_name, 'Administrador')::text,
                   ARRAY[v_prof_role]::text[], 'user'::text,
                   (v_prof_role = 'admin'), false, false;
            RETURN;
        END IF;
    END IF;

    SELECT t.employee_id, t.workspace_id, t.role
    INTO v_emp_id, v_ws_id, v_roles
    FROM public.current_employee_from_token() AS t
    LIMIT 1;

    IF v_ws_id IS NOT NULL THEN
        SELECT e.name
        INTO v_name
        FROM public.employees AS e
        WHERE e.id = v_emp_id
          AND e.workspace_id = v_ws_id
        LIMIT 1;

        RETURN QUERY
        SELECT v_ws_id, NULL::uuid, v_emp_id,
               COALESCE(v_name, 'FuncionÃ¡rio'), v_roles, 'employee'::text,
               ('admin' = ANY(v_roles)), ('tecnico' = ANY(v_roles)),
               ('atendente' = ANY(v_roles));
        RETURN;
    END IF;

    RAISE EXCEPTION 'Acesso negado: Contexto de ator nÃ£o resolvido.';
END;
$$;

CREATE OR REPLACE FUNCTION public.set_ticket_log_actor_name()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_actor_name text;
BEGIN
    BEGIN
        SELECT actor_name INTO v_actor_name
        FROM public.get_current_actor_context();
    EXCEPTION WHEN OTHERS THEN
        v_actor_name := NULL;
    END;

    -- The client never decides who performed an action. Background jobs with
    -- no authenticated context are explicitly identified as Sistema.
    NEW.user_name := COALESCE(NULLIF(btrim(v_actor_name), ''), 'Sistema');

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_ticket_log_actor_name ON public.ticket_logs;
CREATE TRIGGER set_ticket_log_actor_name
BEFORE INSERT ON public.ticket_logs
FOR EACH ROW
EXECUTE FUNCTION public.set_ticket_log_actor_name();

CREATE OR REPLACE FUNCTION public.log_ticket_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_actor_name text;
BEGIN
    BEGIN
        SELECT actor_name INTO v_actor_name
        FROM public.get_current_actor_context();
    EXCEPTION WHEN OTHERS THEN
        v_actor_name := NULL;
    END;

    v_actor_name := COALESCE(NULLIF(btrim(v_actor_name), ''), NULLIF(btrim(NEW.created_by_name), ''), 'Sistema');

    IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
        VALUES (
            NEW.id,
            'AlteraÃ§Ã£o de Status',
            format(
                'A OS **%s** â€” aparelho **%s** do cliente **%s** â€” teve o status alterado de **%s** para **%s** por **%s**.',
                COALESCE(NEW.os_number, 'nÃ£o informada'),
                COALESCE(NEW.device_model, 'nÃ£o informado'),
                COALESCE(NEW.client_name, 'nÃ£o informado'),
                COALESCE(OLD.status, 'nÃ£o informado'),
                COALESCE(NEW.status, 'nÃ£o informado'),
                v_actor_name
            ),
            v_actor_name
        );
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
        VALUES (
            NEW.id,
            'Criado',
            format(
                'A OS **%s** â€” aparelho **%s** do cliente **%s** â€” foi aberta por **%s**.',
                COALESCE(NEW.os_number, 'nÃ£o informada'),
                COALESCE(NEW.device_model, 'nÃ£o informado'),
                COALESCE(NEW.client_name, 'nÃ£o informado'),
                v_actor_name
            ),
            v_actor_name
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_ticket_analysis(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id
      AND workspace_id = v_ctx.workspace_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND OR v_ticket.status <> 'Analise Tecnica' OR v_ticket.analysis_started_at IS NOT NULL THEN
        RAISE EXCEPTION 'A OS nÃ£o estÃ¡ disponÃ­vel para iniciar anÃ¡lise.';
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: TÃ©cnico sÃ³ pode iniciar a prÃ³pria anÃ¡lise.';
    END IF;

    UPDATE public.tickets
    SET analysis_started_at = now(),
        updated_at = now()
    WHERE id = v_ticket.id
      AND workspace_id = v_ctx.workspace_id
    RETURNING * INTO v_ticket;

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        v_ticket.id,
        'Iniciou AnÃ¡lise',
        format(
            'A anÃ¡lise da OS **%s** â€” aparelho **%s** do cliente **%s** â€” foi iniciada por **%s**.',
            COALESCE(v_ticket.os_number, 'nÃ£o informada'),
            COALESCE(v_ticket.device_model, 'nÃ£o informado'),
            COALESCE(v_ticket.client_name, 'nÃ£o informado'),
            v_ctx.actor_name
        ),
        v_ctx.actor_name
    );

    RETURN to_jsonb(v_ticket);
END;
$$;

