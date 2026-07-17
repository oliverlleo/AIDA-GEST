-- Complementa a migração de privacidade: ao definir o nome real, atualiza
-- também os históricos antigos que usavam os rótulos genéricos de administrador.

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
