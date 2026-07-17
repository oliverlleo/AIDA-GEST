-- Impede que e-mails sejam usados como identificação visual no histórico.
-- O nome é apenas informativo; autorização continua baseada em auth.uid(),
-- workspace, perfil e sessão de funcionário.

BEGIN;

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
               COALESCE(v_name, 'Funcionário'), v_roles, 'employee'::text,
               ('admin' = ANY(v_roles)), ('tecnico' = ANY(v_roles)),
               ('atendente' = ANY(v_roles));
        RETURN;
    END IF;

    RAISE EXCEPTION 'Acesso negado: contexto de ator não resolvido.';
END;
$$;

CREATE OR REPLACE FUNCTION public.set_current_user_display_name(p_display_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_catalog
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_workspace_id uuid;
    v_name text := btrim(COALESCE(p_display_name, ''));
    v_email text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: usuário não autenticado.';
    END IF;

    IF char_length(v_name) < 2 OR char_length(v_name) > 80 THEN
        RAISE EXCEPTION 'O nome deve ter entre 2 e 80 caracteres.';
    END IF;

    SELECT w.id INTO v_workspace_id
    FROM public.workspaces AS w
    WHERE w.owner_id = v_uid
    LIMIT 1;

    IF v_workspace_id IS NULL THEN
        SELECT p.workspace_id INTO v_workspace_id
        FROM public.profiles AS p
        WHERE p.id = v_uid
          AND p.role = 'admin'
        LIMIT 1;
    END IF;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Acesso negado: somente administradores podem alterar esta identificação.';
    END IF;

    SELECT u.email INTO v_email
    FROM auth.users AS u
    WHERE u.id = v_uid;

    UPDATE auth.users AS u
    SET raw_user_meta_data = jsonb_set(
            COALESCE(u.raw_user_meta_data, '{}'::jsonb),
            '{full_name}',
            to_jsonb(v_name),
            true
        ),
        updated_at = now()
    WHERE u.id = v_uid;

    IF NULLIF(btrim(v_email), '') IS NOT NULL THEN
        UPDATE public.ticket_logs AS tl
        SET user_name = v_name,
            details = CASE
                WHEN tl.details IS NULL THEN NULL
                ELSE replace(tl.details, tl.user_name, v_name)
            END
        FROM public.tickets AS t
        WHERE t.id = tl.ticket_id
          AND t.workspace_id = v_workspace_id
          AND (
              lower(btrim(tl.user_name)) = lower(btrim(v_email))
              OR tl.user_name IN ('Administrador', 'Admin', 'Owner')
          );
    END IF;

    RETURN v_name;
END;
$$;

REVOKE ALL ON FUNCTION public.set_current_user_display_name(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_current_user_display_name(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_current_user_display_name(text) TO authenticated;

-- Limpa registros antigos que receberam o e-mail do proprietário como autor.
UPDATE public.ticket_logs AS tl
SET user_name = COALESCE(
        NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
        NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
        'Administrador'
    ),
    details = CASE
        WHEN tl.details IS NULL THEN NULL
        ELSE replace(
            tl.details,
            u.email,
            COALESCE(
                NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
                'Administrador'
            )
        )
    END
FROM public.tickets AS t,
     public.workspaces AS w,
     auth.users AS u
WHERE t.id = tl.ticket_id
  AND w.id = t.workspace_id
  AND u.id = w.owner_id
  AND lower(btrim(tl.user_name)) = lower(btrim(u.email));

-- Também cobre administradores autenticados vinculados por profiles.
UPDATE public.ticket_logs AS tl
SET user_name = COALESCE(
        NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
        NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
        'Administrador'
    ),
    details = CASE
        WHEN tl.details IS NULL THEN NULL
        ELSE replace(
            tl.details,
            u.email,
            COALESCE(
                NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
                'Administrador'
            )
        )
    END
FROM public.tickets AS t,
     public.profiles AS p,
     auth.users AS u
WHERE t.id = tl.ticket_id
  AND p.workspace_id = t.workspace_id
  AND p.role = 'admin'
  AND u.id = p.id
  AND lower(btrim(tl.user_name)) = lower(btrim(u.email));

COMMIT;
