-- Supabase Auth for every account; tenant-scoped memberships and verified-email invitations.
-- Apply only after schema recovery and end-to-end verification. No application data is deleted.
BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
CREATE TABLE private.auth_workspace_migration_manifest (
    object_kind text NOT NULL,
    object_key text NOT NULL,
    restore_sql text NOT NULL,
    PRIMARY KEY (object_kind, object_key)
);
REVOKE ALL ON private.auth_workspace_migration_manifest FROM PUBLIC, anon, authenticated;
ALTER TABLE private.auth_workspace_migration_manifest ENABLE ROW LEVEL SECURITY;

INSERT INTO private.auth_workspace_migration_manifest
SELECT 'schema_grant', n.nspname,
    format('REVOKE ALL ON SCHEMA %I FROM PUBLIC, anon, authenticated;', n.nspname) ||
    COALESCE((SELECT string_agg(format(' GRANT %s ON SCHEMA %I TO %s%s;', a.privilege_type,
        n.nspname, CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END,
        CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END), '')
        FROM aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a
        WHERE a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon', 'authenticated')), '')
FROM pg_namespace n WHERE n.nspname = 'private';

-- This receipt contains schema definitions/privileges only, never application records or credentials.
INSERT INTO private.auth_workspace_migration_manifest
SELECT 'function', p.oid::regprocedure::text, pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' OR (n.nspname = 'private' AND p.proname = 'get_schedule_availability');

INSERT INTO private.auth_workspace_migration_manifest
SELECT 'policy', format('%I.%I.%I', schemaname, tablename, policyname),
    format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;', policyname,
        schemaname, tablename, permissive, cmd,
        (SELECT string_agg(CASE WHEN r = 'public' THEN 'PUBLIC' ELSE quote_ident(r) END, ',') FROM unnest(roles) r),
        CASE WHEN qual IS NULL THEN '' ELSE ' USING (' || qual || ')' END,
        CASE WHEN with_check IS NULL THEN '' ELSE ' WITH CHECK (' || with_check || ')' END)
FROM pg_policies WHERE schemaname IN ('public', 'storage');

INSERT INTO private.auth_workspace_migration_manifest
SELECT 'function_grant', p.oid::regprocedure::text,
    format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated;', p.oid::regprocedure) ||
    COALESCE((SELECT string_agg(format(' GRANT %s ON FUNCTION %s TO %s%s;', a.privilege_type,
        p.oid::regprocedure, CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END,
        CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END), '')
        FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
        WHERE a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon', 'authenticated')), '')
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public';

INSERT INTO private.auth_workspace_migration_manifest
SELECT 'table_grant', c.oid::regclass::text,
    format('REVOKE ALL ON TABLE %s FROM PUBLIC, anon, authenticated;', c.oid::regclass) ||
    COALESCE((SELECT string_agg(format(' GRANT %s ON TABLE %s TO %s%s;', a.privilege_type,
        c.oid::regclass, CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END,
        CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END), '')
        FROM aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
        WHERE a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon', 'authenticated')), '') ||
    COALESCE((SELECT string_agg(format(' REVOKE ALL (%I) ON TABLE %s FROM PUBLIC, anon, authenticated;', at.attname, c.oid::regclass) ||
        COALESCE((SELECT string_agg(format(' GRANT %s (%I) ON TABLE %s TO %s%s;', a.privilege_type,
            at.attname, c.oid::regclass, CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END,
            CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END), '')
            FROM aclexplode(at.attacl) a WHERE a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon', 'authenticated')), '') , '')
        FROM pg_attribute at WHERE at.attrelid = c.oid AND at.attnum > 0 AND NOT at.attisdropped), '')
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');

ALTER TABLE public.employees ADD COLUMN legacy_auth_disabled boolean NOT NULL DEFAULT false;
UPDATE public.employees SET legacy_auth_disabled = true;
ALTER TABLE public.profiles ALTER COLUMN role DROP DEFAULT;

CREATE TABLE public.workspace_memberships (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    employee_id uuid,
    member_kind text NOT NULL CHECK (member_kind IN ('owner', 'employee')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'blocked', 'revoked')),
    session_valid_after timestamptz NOT NULL DEFAULT '-infinity',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, user_id),
    UNIQUE (employee_id),
    FOREIGN KEY (workspace_id, employee_id) REFERENCES public.employees(workspace_id, id) ON DELETE RESTRICT,
    CHECK ((member_kind = 'owner' AND employee_id IS NULL) OR (member_kind = 'employee' AND employee_id IS NOT NULL))
);
CREATE INDEX workspace_memberships_user_access ON public.workspace_memberships(user_id, status);
ALTER TABLE public.workspace_memberships ENABLE ROW LEVEL SECURITY;
INSERT INTO public.workspace_memberships(workspace_id, user_id, member_kind)
SELECT id, owner_id, 'owner' FROM public.workspaces;

CREATE TABLE public.workspace_invitations (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    employee_id uuid NOT NULL,
    email text NOT NULL CHECK (email = lower(btrim(email)) AND length(email) BETWEEN 3 AND 254),
    invited_by uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'cancelled')),
    expires_at timestamptz NOT NULL DEFAULT now() + interval '7 days',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    accepted_by uuid REFERENCES auth.users(id),
    accepted_at timestamptz,
    last_delivery_status text NOT NULL DEFAULT 'not_sent' CHECK (last_delivery_status IN ('not_sent', 'sending', 'queued', 'failed')),
    last_delivery_at timestamptz,
    last_delivery_attempt_at timestamptz,
    last_delivery_attempt_id uuid,
    delivery_attempts integer NOT NULL DEFAULT 0 CHECK (delivery_attempts >= 0),
    last_delivery_error_code text,
    FOREIGN KEY (workspace_id, employee_id) REFERENCES public.employees(workspace_id, id) ON DELETE RESTRICT,
    CHECK ((status = 'accepted' AND accepted_by IS NOT NULL AND accepted_at IS NOT NULL)
        OR (status <> 'accepted' AND accepted_by IS NULL AND accepted_at IS NULL))
);
CREATE UNIQUE INDEX workspace_invitation_pending_employee ON public.workspace_invitations(employee_id) WHERE status = 'pending';
CREATE UNIQUE INDEX workspace_invitation_pending_email ON public.workspace_invitations(workspace_id, email) WHERE status = 'pending';
CREATE INDEX workspace_invitation_email_pending ON public.workspace_invitations(email, expires_at) WHERE status = 'pending';
ALTER TABLE public.workspace_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.workspace_memberships, public.workspace_invitations FROM PUBLIC, anon, authenticated;

CREATE FUNCTION private.auth_identity()
RETURNS TABLE(user_id uuid, email text, session_id uuid, session_created_at timestamptz, display_name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_sid uuid; v_user record; v_session timestamptz;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Acesso negado: autentique sua conta.' USING ERRCODE = '42501'; END IF;
    SELECT u.email, u.email_confirmed_at, u.is_anonymous, u.banned_until, u.deleted_at,
        COALESCE(NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''), NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''), 'Usuario') AS name
    INTO v_user FROM auth.users u WHERE u.id = v_uid;
    IF NOT FOUND OR v_user.deleted_at IS NOT NULL OR v_user.email_confirmed_at IS NULL OR COALESCE(v_user.is_anonymous, false)
       OR (v_user.banned_until IS NOT NULL AND v_user.banned_until > now()) THEN
        RAISE EXCEPTION 'Acesso negado: confirme seu e-mail para continuar.' USING ERRCODE = '42501';
    END IF;
    BEGIN v_sid := NULLIF(auth.jwt() ->> 'session_id', '')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN v_sid := NULL; END;
    SELECT s.created_at INTO v_session FROM auth.sessions s WHERE s.id = v_sid AND s.user_id = v_uid;
    IF v_session IS NULL THEN RAISE EXCEPTION 'Sessao invalida: entre novamente.' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT v_uid, lower(btrim(v_user.email)), v_sid, v_session, v_user.name::text;
END $$;

CREATE FUNCTION private.requested_workspace()
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE v_headers jsonb; v_value text; v_workspace uuid;
BEGIN
    BEGIN
        v_headers := NULLIF(current_setting('request.headers', true), '')::jsonb;
        v_value := NULLIF(btrim(v_headers ->> 'x-workspace-id'), '');
        v_workspace := v_value::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'Empresa selecionada invalida.' USING ERRCODE = '42501';
    END;
    IF v_workspace IS NULL THEN RAISE EXCEPTION 'Selecione uma empresa para continuar.' USING ERRCODE = '42501'; END IF;
    RETURN v_workspace;
END $$;

CREATE FUNCTION private.workspace_actor(p_workspace_id uuid)
RETURNS TABLE(workspace_id uuid, actor_user_id uuid, actor_employee_id uuid, actor_name text, actor_roles text[], actor_kind text,
    is_admin boolean, is_technician boolean, is_attendant boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_identity record; v_member record; v_employee record;
BEGIN
    SELECT * INTO v_identity FROM private.auth_identity();
    SELECT m.*, w.owner_id INTO v_member FROM public.workspace_memberships m
    JOIN public.workspaces w ON w.id = m.workspace_id
    WHERE m.workspace_id = p_workspace_id AND m.user_id = v_identity.user_id AND m.status = 'active';
    IF NOT FOUND THEN RAISE EXCEPTION 'Acesso negado a esta empresa.' USING ERRCODE = '42501'; END IF;
    IF v_identity.session_created_at <= v_member.session_valid_after THEN
        RAISE EXCEPTION 'Reautenticacao necessaria para acessar esta empresa.' USING ERRCODE = '42501';
    END IF;
    IF v_member.member_kind = 'owner' THEN
        IF v_member.owner_id <> v_identity.user_id THEN RAISE EXCEPTION 'Vinculo de proprietario invalido.' USING ERRCODE = '42501'; END IF;
        RETURN QUERY SELECT p_workspace_id, v_identity.user_id, NULL::uuid, v_identity.display_name::text,
            ARRAY['admin']::text[], 'user'::text, true, false, false;
    ELSE
        SELECT e.* INTO v_employee FROM public.employees e WHERE e.id = v_member.employee_id
            AND e.workspace_id = p_workspace_id AND e.deleted_at IS NULL AND NOT e.legacy_auth_disabled;
        IF NOT FOUND OR EXISTS(SELECT 1 FROM public.employee_auth_state a WHERE a.employee_id = v_member.employee_id AND a.manual_blocked) THEN
            RAISE EXCEPTION 'Acesso do funcionario bloqueado ou removido.' USING ERRCODE = '42501';
        END IF;
        RETURN QUERY SELECT p_workspace_id, NULL::uuid, v_employee.id::uuid, v_employee.name::text,
            COALESCE(v_employee.roles, '{}'::text[]), 'employee'::text,
            'admin' = ANY(COALESCE(v_employee.roles, '{}'::text[])),
            'tecnico' = ANY(COALESCE(v_employee.roles, '{}'::text[])),
            'atendente' = ANY(COALESCE(v_employee.roles, '{}'::text[]));
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_current_actor_context()
RETURNS TABLE(workspace_id uuid, actor_user_id uuid, actor_employee_id uuid, actor_name text, actor_roles text[], actor_kind text,
    is_admin boolean, is_technician boolean, is_attendant boolean)
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    SELECT * FROM private.workspace_actor(private.requested_workspace());
$$;

CREATE FUNCTION private.has_workspace_permission(p_workspace_id uuid, p_permission text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor record;
BEGIN
    IF p_workspace_id IS DISTINCT FROM private.requested_workspace() THEN RETURN false; END IF;
    SELECT * INTO v_actor FROM private.workspace_actor(p_workspace_id);
    IF p_permission = 'member' THEN RETURN true; END IF;
    IF v_actor.is_admin THEN RETURN true; END IF;
    IF p_permission = 'operational_read' THEN RETURN v_actor.is_attendant OR v_actor.is_technician OR 'tester' = ANY(v_actor.actor_roles); END IF;
    IF p_permission = 'catalog_read' THEN RETURN v_actor.is_attendant OR v_actor.is_technician OR 'tester' = ANY(v_actor.actor_roles); END IF;
    IF p_permission IN ('ticket_photo_write', 'inventory_read') THEN RETURN v_actor.is_attendant OR v_actor.is_technician; END IF;
    IF p_permission IN ('catalog_write', 'customer_access') THEN RETURN v_actor.is_attendant; END IF;
    RETURN false;
EXCEPTION WHEN insufficient_privilege THEN RETURN false;
END $$;

CREATE OR REPLACE FUNCTION public.can_manage_workspace(p_workspace_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.has_workspace_permission(p_workspace_id, 'admin');
$$;

CREATE FUNCTION private.assert_workspace_manager(p_workspace_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NOT public.can_manage_workspace(p_workspace_id) THEN
        RAISE EXCEPTION 'Permissao negada: administrador desta empresa necessario.' USING ERRCODE = '42501';
    END IF;
END $$;

CREATE FUNCTION private.assert_employee_roles(p_roles text[])
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF p_roles IS NULL OR cardinality(p_roles) = 0 OR cardinality(p_roles) > 4
       OR EXISTS(SELECT 1 FROM unnest(p_roles) r WHERE r IS NULL OR r NOT IN ('admin', 'atendente', 'tecnico', 'tester')) THEN
        RAISE EXCEPTION 'Selecione permissoes validas para o funcionario.' USING ERRCODE = '22023';
    END IF;
END $$;

CREATE FUNCTION public.list_my_workspaces()
RETURNS TABLE(workspace_id uuid, workspace_name text, member_kind text, employee_id uuid, name text, roles text[],
    whatsapp_number text, tracker_config jsonb, requires_reauthentication boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_identity record;
BEGIN
    SELECT * INTO v_identity FROM private.auth_identity();
    RETURN QUERY SELECT w.id, w.name, m.member_kind, m.employee_id,
        CASE WHEN m.member_kind = 'owner' THEN v_identity.display_name ELSE e.name END,
        CASE WHEN m.member_kind = 'owner' THEN ARRAY['admin']::text[] ELSE COALESCE(e.roles, '{}'::text[]) END,
        CASE WHEN v_identity.session_created_at > m.session_valid_after THEN w.whatsapp_number END,
        CASE WHEN v_identity.session_created_at > m.session_valid_after THEN w.tracker_config END,
        v_identity.session_created_at <= m.session_valid_after
    FROM public.workspace_memberships m JOIN public.workspaces w ON w.id = m.workspace_id
    LEFT JOIN public.employees e ON e.id = m.employee_id AND e.workspace_id = m.workspace_id
    LEFT JOIN public.employee_auth_state a ON a.employee_id = e.id
    WHERE m.user_id = v_identity.user_id AND m.status = 'active'
      AND ((m.member_kind = 'owner' AND w.owner_id = m.user_id)
        OR (m.member_kind = 'employee' AND e.deleted_at IS NULL AND NOT e.legacy_auth_disabled AND NOT COALESCE(a.manual_blocked, false)))
    ORDER BY w.name, w.id;
END $$;

CREATE FUNCTION public.get_my_access_context(p_workspace_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor record; v_identity record; v_member uuid; v_workspace record;
BEGIN
    SELECT * INTO v_actor FROM private.workspace_actor(p_workspace_id);
    SELECT * INTO v_identity FROM private.auth_identity();
    SELECT m.id INTO v_member FROM public.workspace_memberships m WHERE m.workspace_id = p_workspace_id AND m.user_id = v_identity.user_id;
    SELECT w.name, w.whatsapp_number, w.tracker_config INTO v_workspace FROM public.workspaces w WHERE w.id = p_workspace_id;
    RETURN jsonb_build_object('workspace_id', p_workspace_id, 'workspace_name', v_workspace.name,
        'member_kind', CASE WHEN v_actor.actor_kind = 'user' THEN 'owner' ELSE 'employee' END,
        'employee_id', v_actor.actor_employee_id, 'name', v_actor.actor_name, 'roles', v_actor.actor_roles,
        'whatsapp_number', v_workspace.whatsapp_number, 'tracker_config', v_workspace.tracker_config,
        'auth_user_id', v_identity.user_id, 'membership_id', v_member, 'requires_reauthentication', false);
END $$;

CREATE FUNCTION public.create_company_workspace(p_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_identity record; v_id uuid;
BEGIN
    SELECT * INTO v_identity FROM private.auth_identity();
    IF char_length(btrim(COALESCE(p_name, ''))) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'Nome da empresa deve ter entre 2 e 120 caracteres.' USING ERRCODE = '22023'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_identity.user_id::text, 0));
    IF EXISTS(SELECT 1 FROM public.workspaces WHERE owner_id = v_identity.user_id) THEN
        RAISE EXCEPTION 'Esta conta ja possui uma empresa propria.' USING ERRCODE = '23505';
    END IF;
    INSERT INTO public.workspaces(name, company_code, owner_id) VALUES (btrim(p_name), 'internal_' || extensions.gen_random_uuid()::text, v_identity.user_id) RETURNING id INTO v_id;
    INSERT INTO public.workspace_memberships(workspace_id, user_id, member_kind) VALUES(v_id, v_identity.user_id, 'owner');
    INSERT INTO public.profiles(id) VALUES(v_identity.user_id) ON CONFLICT(id) DO NOTHING;
    RETURN v_id;
END $$;

CREATE FUNCTION public.list_my_pending_invitations()
RETURNS TABLE(invitation_id uuid, workspace_id uuid, workspace_name text, employee_id uuid, name text, email text,
    roles text[], expires_at timestamptz, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_identity record;
BEGIN
    SELECT * INTO v_identity FROM private.auth_identity();
    RETURN QUERY SELECT i.id, i.workspace_id, w.name, e.id, e.name, i.email, e.roles, i.expires_at, i.created_at
    FROM public.workspace_invitations i JOIN public.workspaces w ON w.id = i.workspace_id
    JOIN public.employees e ON e.id = i.employee_id AND e.workspace_id = i.workspace_id
    WHERE i.email = v_identity.email AND i.status = 'pending' AND i.expires_at > now()
      AND e.deleted_at IS NULL AND NOT e.legacy_auth_disabled
    ORDER BY i.created_at DESC, i.id;
END $$;

CREATE FUNCTION public.get_my_workspace_invitations(p_workspace_id uuid)
RETURNS TABLE(invitation_id uuid, workspace_id uuid, workspace_name text, employee_id uuid, name text, email text,
    roles text[], expires_at timestamptz, created_at timestamptz, status text, last_delivery_status text, last_delivery_at timestamptz, delivery_attempts integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM private.assert_workspace_manager(p_workspace_id);
    RETURN QUERY SELECT i.id, i.workspace_id, w.name, e.id, e.name, i.email, e.roles, i.expires_at, i.created_at,
        i.status, i.last_delivery_status, i.last_delivery_at, i.delivery_attempts
    FROM public.workspace_invitations i JOIN public.workspaces w ON w.id = i.workspace_id
    JOIN public.employees e ON e.id = i.employee_id AND e.workspace_id = i.workspace_id
    WHERE i.workspace_id = p_workspace_id AND NOT e.legacy_auth_disabled ORDER BY i.created_at DESC, i.id;
END $$;

CREATE FUNCTION public.create_workspace_invitation(p_workspace_id uuid, p_name text, p_email text, p_roles text[], p_employee_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_employee uuid; v_id uuid; v_email text := lower(btrim(COALESCE(p_email, '')));
BEGIN
    PERFORM private.assert_workspace_manager(p_workspace_id);
    PERFORM private.assert_employee_roles(p_roles);
    IF char_length(btrim(COALESCE(p_name, ''))) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'Nome deve ter entre 2 e 80 caracteres.' USING ERRCODE = '22023'; END IF;
    IF length(v_email) > 254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'E-mail invalido.' USING ERRCODE = '22023'; END IF;
    IF EXISTS(SELECT 1 FROM public.workspace_memberships m JOIN auth.users u ON u.id = m.user_id
        WHERE m.workspace_id = p_workspace_id AND lower(btrim(u.email)) = v_email AND m.status <> 'revoked') THEN
        RAISE EXCEPTION 'Esta conta ja tem vinculo com a empresa.' USING ERRCODE = '23505';
    END IF;
    IF p_employee_id IS NULL THEN
        INSERT INTO public.employees(workspace_id, name, username, password_hash, roles, must_change_password)
        VALUES(p_workspace_id, btrim(p_name), 'auth_' || extensions.gen_random_uuid()::text,
            extensions.crypt(encode(extensions.gen_random_bytes(32), 'hex'), extensions.gen_salt('bf', 10)),
            ARRAY(SELECT DISTINCT r FROM unnest(p_roles) r ORDER BY r), false)
        RETURNING id INTO v_employee;
    ELSE
        SELECT e.id INTO v_employee FROM public.employees e WHERE e.id = p_employee_id AND e.workspace_id = p_workspace_id
            AND NOT e.legacy_auth_disabled AND e.deleted_at IS NULL FOR UPDATE;
        IF v_employee IS NULL OR EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = v_employee) THEN
            RAISE EXCEPTION 'Funcionario invalido ou ja associado.' USING ERRCODE = '42501';
        END IF;
        UPDATE public.employees SET name = btrim(p_name), roles = ARRAY(SELECT DISTINCT r FROM unnest(p_roles) r ORDER BY r) WHERE id = v_employee;
        UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE employee_id = v_employee AND status = 'pending';
    END IF;
    INSERT INTO public.workspace_invitations(workspace_id, employee_id, email, invited_by)
    VALUES(p_workspace_id, v_employee, v_email, auth.uid()) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE FUNCTION public.reissue_workspace_invitation(p_invitation_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_inv public.workspace_invitations%rowtype; v_id uuid;
BEGIN
    SELECT * INTO v_inv FROM public.workspace_invitations WHERE id = p_invitation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Convite nao encontrado.' USING ERRCODE = '22023'; END IF;
    PERFORM private.assert_workspace_manager(v_inv.workspace_id);
    IF v_inv.status = 'accepted' OR EXISTS(SELECT 1 FROM public.workspace_memberships WHERE employee_id = v_inv.employee_id) THEN
        RAISE EXCEPTION 'Funcionario ja associado.' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.employees WHERE id = v_inv.employee_id AND deleted_at IS NULL AND NOT legacy_auth_disabled) THEN
        RAISE EXCEPTION 'Funcionario removido.' USING ERRCODE = '22023';
    END IF;
    UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE employee_id = v_inv.employee_id AND status = 'pending';
    INSERT INTO public.workspace_invitations(workspace_id, employee_id, email, invited_by)
    VALUES(v_inv.workspace_id, v_inv.employee_id, v_inv.email, auth.uid()) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE FUNCTION public.cancel_workspace_invitation(p_invitation_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_inv public.workspace_invitations%rowtype;
BEGIN
    SELECT * INTO v_inv FROM public.workspace_invitations WHERE id = p_invitation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Convite nao encontrado.' USING ERRCODE = '22023'; END IF;
    PERFORM private.assert_workspace_manager(v_inv.workspace_id);
    IF v_inv.status = 'accepted' THEN RAISE EXCEPTION 'Convite ja aceito; gerencie o vinculo do funcionario.' USING ERRCODE = '22023'; END IF;
    UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE id = p_invitation_id;
END $$;

CREATE FUNCTION public.accept_workspace_invitation(p_invitation_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_identity record; v_inv public.workspace_invitations%rowtype; v_employee record; v_existing public.workspace_memberships%rowtype;
BEGIN
    SELECT * INTO v_identity FROM private.auth_identity();
    SELECT * INTO v_inv FROM public.workspace_invitations WHERE id = p_invitation_id FOR UPDATE;
    IF NOT FOUND OR v_inv.email <> v_identity.email THEN RAISE EXCEPTION 'Convite invalido para esta conta.' USING ERRCODE = '42501'; END IF;
    IF v_inv.status = 'accepted' AND v_inv.accepted_by = v_identity.user_id THEN RETURN v_inv.workspace_id; END IF;
    IF v_inv.status <> 'pending' OR v_inv.expires_at <= now() THEN RAISE EXCEPTION 'Convite expirado ou cancelado.' USING ERRCODE = '22023'; END IF;
    SELECT e.* INTO v_employee FROM public.employees e WHERE e.id = v_inv.employee_id AND e.workspace_id = v_inv.workspace_id FOR UPDATE;
    IF v_employee.id IS NULL OR v_employee.deleted_at IS NOT NULL OR v_employee.legacy_auth_disabled
       OR EXISTS(SELECT 1 FROM public.employee_auth_state a WHERE a.employee_id = v_inv.employee_id AND a.manual_blocked) THEN
        RAISE EXCEPTION 'Funcionario indisponivel.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_existing FROM public.workspace_memberships m
    WHERE m.workspace_id = v_inv.workspace_id AND m.user_id = v_identity.user_id FOR UPDATE;
    IF FOUND THEN
        IF v_existing.member_kind <> 'employee' OR v_existing.status <> 'revoked' THEN
            RAISE EXCEPTION 'Esta conta ja possui vinculo nesta empresa.' USING ERRCODE = '23505';
        END IF;
        UPDATE public.workspace_memberships SET employee_id = v_inv.employee_id, status = 'active', session_valid_after = '-infinity'
        WHERE id = v_existing.id;
    ELSE
        INSERT INTO public.workspace_memberships(workspace_id, user_id, employee_id, member_kind)
        VALUES(v_inv.workspace_id, v_identity.user_id, v_inv.employee_id, 'employee');
    END IF;
    UPDATE public.workspace_invitations SET status = 'accepted', accepted_by = v_identity.user_id, accepted_at = now(), updated_at = now() WHERE id = v_inv.id;
    INSERT INTO public.profiles(id) VALUES(v_identity.user_id) ON CONFLICT(id) DO NOTHING;
    RETURN v_inv.workspace_id;
END $$;

CREATE FUNCTION public.list_workspace_staff(p_workspace_id uuid)
RETURNS TABLE(id uuid, name text, username text, roles text[], created_at timestamptz, workspace_id uuid, email text,
    auth_user_id uuid, access_status text, invitation_id uuid, invitation_status text, invitation_expires_at timestamptz, last_delivery_status text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM private.assert_workspace_manager(p_workspace_id);
    RETURN QUERY SELECT e.id, e.name, e.username, e.roles, e.created_at, e.workspace_id, COALESCE(u.email::text, i.email), m.user_id,
        CASE WHEN e.deleted_at IS NOT NULL OR m.status = 'revoked' THEN 'removed'
             WHEN m.status = 'blocked' OR COALESCE(a.manual_blocked, false) THEN 'blocked'
             WHEN m.id IS NOT NULL THEN 'active' ELSE 'pending' END,
        i.id, i.status, i.expires_at, i.last_delivery_status
    FROM public.employees e LEFT JOIN public.workspace_memberships m ON m.employee_id = e.id
    LEFT JOIN auth.users u ON u.id = m.user_id LEFT JOIN public.employee_auth_state a ON a.employee_id = e.id
    LEFT JOIN LATERAL(SELECT inv.* FROM public.workspace_invitations inv WHERE inv.employee_id = e.id ORDER BY inv.created_at DESC, inv.id LIMIT 1) i ON true
    WHERE e.workspace_id = p_workspace_id AND NOT e.legacy_auth_disabled ORDER BY e.created_at DESC, e.id;
END $$;

CREATE FUNCTION public.update_employee_access(p_employee_id uuid, p_name text, p_roles text[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_workspace uuid;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    PERFORM private.assert_employee_roles(p_roles);
    IF char_length(btrim(COALESCE(p_name, ''))) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'Nome deve ter entre 2 e 80 caracteres.' USING ERRCODE = '22023'; END IF;
    IF EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = p_employee_id AND m.user_id = auth.uid())
       AND NOT 'admin' = ANY(p_roles) THEN RAISE EXCEPTION 'Voce nao pode remover sua propria permissao administrativa.' USING ERRCODE = '42501'; END IF;
    UPDATE public.employees SET name = btrim(p_name), roles = ARRAY(SELECT DISTINCT r FROM unnest(p_roles) r ORDER BY r) WHERE id = p_employee_id;
END $$;

CREATE OR REPLACE FUNCTION public.set_employee_account_blocked(p_employee_id uuid, p_blocked boolean, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_workspace uuid;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    IF p_blocked IS NULL THEN RAISE EXCEPTION 'Estado de bloqueio obrigatorio.' USING ERRCODE = '22023'; END IF;
    IF p_blocked AND EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = p_employee_id AND m.user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Voce nao pode bloquear seu proprio acesso.' USING ERRCODE = '42501'; END IF;
    IF length(p_reason) > 500 THEN RAISE EXCEPTION 'Motivo muito longo.' USING ERRCODE = '22023'; END IF;
    INSERT INTO public.employee_auth_state(employee_id, manual_blocked, manual_blocked_at, manual_block_reason)
    VALUES(p_employee_id, p_blocked, CASE WHEN p_blocked THEN now() END, CASE WHEN p_blocked THEN NULLIF(btrim(p_reason), '') END)
    ON CONFLICT(employee_id) DO UPDATE SET manual_blocked = excluded.manual_blocked, manual_blocked_at = excluded.manual_blocked_at,
        manual_block_reason = excluded.manual_block_reason, updated_at = now();
    UPDATE public.workspace_memberships SET status = CASE WHEN p_blocked THEN 'blocked' ELSE 'active' END,
        session_valid_after = CASE WHEN p_blocked THEN now() ELSE session_valid_after END
    WHERE employee_id = p_employee_id AND status <> 'revoked';
END $$;

CREATE OR REPLACE FUNCTION public.revoke_employee_sessions(p_employee_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_workspace uuid; v_count integer;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    UPDATE public.workspace_memberships SET session_valid_after = now() WHERE employee_id = p_employee_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;

CREATE FUNCTION public.set_employee_removed(p_employee_id uuid, p_removed boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_workspace uuid;
BEGIN
    SELECT e.workspace_id INTO v_workspace FROM public.employees e WHERE e.id = p_employee_id AND NOT e.legacy_auth_disabled FOR UPDATE;
    PERFORM private.assert_workspace_manager(v_workspace);
    IF p_removed IS NULL THEN RAISE EXCEPTION 'Estado de remocao obrigatorio.' USING ERRCODE = '22023'; END IF;
    IF p_removed AND EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.employee_id = p_employee_id AND m.user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Voce nao pode remover seu proprio acesso.' USING ERRCODE = '42501'; END IF;
    UPDATE public.employees SET deleted_at = CASE WHEN p_removed THEN now() END WHERE id = p_employee_id;
    UPDATE public.workspace_memberships SET status = CASE WHEN p_removed THEN 'revoked'
        WHEN EXISTS(SELECT 1 FROM public.employee_auth_state a WHERE a.employee_id = p_employee_id AND a.manual_blocked) THEN 'blocked' ELSE 'active' END,
        session_valid_after = CASE WHEN p_removed THEN now() ELSE session_valid_after END WHERE employee_id = p_employee_id;
    IF p_removed THEN UPDATE public.workspace_invitations SET status = 'cancelled', updated_at = now() WHERE employee_id = p_employee_id AND status = 'pending'; END IF;
END $$;

CREATE FUNCTION private.invitation_delivery_details(p_invitation_id uuid, p_requester_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_inv record;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' OR p_requester_user_id IS NULL THEN RAISE EXCEPTION 'Entrega disponivel apenas ao servidor.' USING ERRCODE = '42501'; END IF;
    SELECT i.*, w.name AS workspace_name, e.name AS employee_name INTO v_inv
    FROM public.workspace_invitations i JOIN public.workspaces w ON w.id = i.workspace_id JOIN public.employees e ON e.id = i.employee_id
    WHERE i.id = p_invitation_id AND i.status = 'pending' AND i.expires_at > now() AND e.deleted_at IS NULL AND NOT e.legacy_auth_disabled;
    IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.workspace_memberships m JOIN public.workspaces w ON w.id = m.workspace_id
        LEFT JOIN public.employees e ON e.id = m.employee_id LEFT JOIN public.employee_auth_state a ON a.employee_id = e.id
        WHERE m.user_id = p_requester_user_id AND m.workspace_id = v_inv.workspace_id AND m.status = 'active'
          AND ((m.member_kind = 'owner' AND w.owner_id = m.user_id) OR (e.deleted_at IS NULL AND NOT e.legacy_auth_disabled
            AND NOT COALESCE(a.manual_blocked, false) AND 'admin' = ANY(COALESCE(e.roles, '{}'::text[]))))) THEN
        RAISE EXCEPTION 'Permissao negada para entregar o convite.' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object('invitation_id', v_inv.id, 'workspace_id', v_inv.workspace_id, 'workspace_name', v_inv.workspace_name,
        'employee_id', v_inv.employee_id, 'name', v_inv.employee_name, 'email', v_inv.email, 'expires_at', v_inv.expires_at,
        'roles', (SELECT e.roles FROM public.employees e WHERE e.id = v_inv.employee_id),
        'last_delivery_at', v_inv.last_delivery_at, 'last_delivery_attempt_at', v_inv.last_delivery_attempt_at,
        'delivery_attempts', v_inv.delivery_attempts);
END $$;

CREATE FUNCTION public.get_invitation_delivery_details(p_invitation_id uuid, p_requester_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_details jsonb; v_inv public.workspace_invitations%rowtype; v_claim uuid;
BEGIN
    v_details := private.invitation_delivery_details(p_invitation_id, p_requester_user_id);
    SELECT * INTO v_inv FROM public.workspace_invitations WHERE id = p_invitation_id FOR UPDATE;
    IF v_inv.status <> 'pending' OR v_inv.expires_at <= now() THEN RAISE EXCEPTION 'INVITATION_UNAVAILABLE' USING ERRCODE = '22023'; END IF;
    IF (v_inv.last_delivery_status = 'sending' AND v_inv.last_delivery_attempt_at > clock_timestamp() - interval '2 minutes')
        OR v_inv.last_delivery_attempt_at > clock_timestamp() - interval '60 seconds' THEN
        RAISE EXCEPTION 'INVITATION_DELIVERY_COOLDOWN' USING ERRCODE = 'PT429';
    END IF;
    v_claim := extensions.gen_random_uuid();
    UPDATE public.workspace_invitations SET last_delivery_status = 'sending', last_delivery_attempt_at = clock_timestamp(),
        last_delivery_attempt_id = v_claim, delivery_attempts = delivery_attempts + 1,
        last_delivery_error_code = NULL, updated_at = now() WHERE id = p_invitation_id;
    RETURN v_details || jsonb_build_object('delivery_attempt_id', v_claim, 'delivery_attempts', v_inv.delivery_attempts + 1);
END $$;

CREATE FUNCTION public.mark_invitation_delivery(p_invitation_id uuid, p_requester_user_id uuid, p_delivery_attempt_id uuid, p_delivered boolean, p_error_code text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM private.invitation_delivery_details(p_invitation_id, p_requester_user_id);
    IF p_delivered IS NULL OR length(p_error_code) > 80 OR COALESCE(p_error_code, '') !~ '^[a-zA-Z0-9_.:-]*$' THEN
        RAISE EXCEPTION 'Resultado de entrega invalido.' USING ERRCODE = '22023'; END IF;
    UPDATE public.workspace_invitations SET last_delivery_status = CASE WHEN p_delivered THEN 'queued' ELSE 'failed' END,
        last_delivery_at = now(),
        last_delivery_error_code = CASE WHEN p_delivered THEN NULL ELSE p_error_code END, updated_at = now()
    WHERE id = p_invitation_id AND last_delivery_attempt_id = p_delivery_attempt_id AND last_delivery_status = 'sending';
    IF NOT FOUND THEN RAISE EXCEPTION 'INVITATION_DELIVERY_CLAIM_INVALID' USING ERRCODE = '22023'; END IF;
END $$;

-- Remaining legacy resolvers, operational policies, Storage and privileges follow below.
CREATE OR REPLACE FUNCTION public.get_dashboard_kpis(p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_technician_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_defect text DEFAULT NULL::text, p_device_model text DEFAULT NULL::text, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_workspace_id UUID;
    v_user_id UUID;
    v_role TEXT;
    v_result JSONB;
BEGIN
    SELECT ctx.workspace_id INTO v_workspace_id FROM public.get_current_actor_context() ctx;

    -- 2. QUERY LOGIC (Identical to original but enforcing v_workspace_id)
    WITH filtered_tickets AS (
        SELECT
            t.*,
            COALESCE(t.repair_end_at, CASE WHEN t.status = 'Finalizado' THEN t.updated_at ELSE NULL END) as effective_repair_end,
            EXTRACT(EPOCH FROM (t.repair_end_at - t.repair_start_at)) as duration_repair_sec,
            EXTRACT(EPOCH FROM (COALESCE(t.pickup_available_at, t.repair_end_at) - t.created_at)) as duration_solution_sec,
            EXTRACT(EPOCH FROM (t.delivered_at - t.created_at)) as duration_delivery_sec,
            EXTRACT(EPOCH FROM (t.budget_sent_at - t.created_at)) as duration_budget_sec,
            EXTRACT(EPOCH FROM (t.pickup_available_at - t.created_at)) as duration_pickup_notify_sec
        FROM
            public.tickets t
        WHERE
            t.workspace_id = v_workspace_id -- ENFORCED HERE
            AND t.deleted_at IS NULL
            AND (p_date_start IS NULL OR t.created_at >= p_date_start::timestamp)
            AND (p_date_end IS NULL OR t.created_at <= (p_date_end::timestamp + INTERVAL '1 day' - INTERVAL '1 millisecond'))
            AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
            AND (p_status IS NULL OR p_status = 'all' OR t.status = p_status)
            AND (p_device_model IS NULL OR p_device_model = 'all' OR t.device_model = p_device_model)
            AND (p_defect IS NULL OR p_defect = 'all' OR t.defect_reported ILIKE '%' || p_defect || '%')
            AND (p_search IS NULL OR
                 t.client_name ILIKE '%' || p_search || '%' OR
                 t.os_number ILIKE '%' || p_search || '%' OR
                 t.device_model ILIKE '%' || p_search || '%' OR
                 t.serial_number ILIKE '%' || p_search || '%' OR
                 t.contact_info ILIKE '%' || p_search || '%'
            )
    ),
    expanded_defects AS (
        SELECT
            trim(defect) as defect_name,
            repair_successful,
            duration_repair_sec,
            duration_solution_sec,
            duration_delivery_sec,
            device_model,
            technician_id
        FROM
            filtered_tickets,
            unnest(string_to_array(defect_reported, ',')) as defect
        WHERE
            trim(defect) <> ''
    ),
    stats AS (
        SELECT
            count(*) as total_tickets,
            count(*) FILTER (WHERE status = 'Analise Tecnica') as analysis_count,
            count(*) FILTER (WHERE status = 'Andamento Reparo') as repair_count,
            count(*) FILTER (WHERE repair_successful IS NOT NULL) as total_with_outcome,
            count(*) FILTER (WHERE repair_successful = TRUE) as success_count,
            avg(duration_repair_sec) FILTER (WHERE duration_repair_sec > 0) as avg_repair_sec,
            avg(duration_solution_sec) FILTER (WHERE duration_solution_sec > 0) as avg_solution_sec,
            avg(duration_delivery_sec) FILTER (WHERE duration_delivery_sec > 0) as avg_delivery_sec,
            avg(duration_budget_sec) FILTER (WHERE duration_budget_sec > 0) as avg_budget_sec,
            avg(duration_pickup_notify_sec) FILTER (WHERE duration_pickup_notify_sec > 0) as avg_pickup_notify_sec,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '1 day')) as tickets_today,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '7 days')) as tickets_week,
            count(*) FILTER (WHERE created_at >= (now() - INTERVAL '30 days')) as tickets_month,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '1 day')) as repairs_today,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '7 days')) as repairs_week,
            count(*) FILTER (WHERE effective_repair_end >= (now() - INTERVAL '30 days')) as repairs_month,
            count(*) FILTER (WHERE delivery_method = 'pickup') as pickup_total,
            count(*) FILTER (WHERE delivery_method = 'pickup' AND repair_successful = TRUE) as pickup_success,
            count(*) FILTER (WHERE delivery_method = 'pickup' AND repair_successful = FALSE) as pickup_fail,
            count(*) FILTER (WHERE delivery_method = 'carrier') as carrier_total,
            count(*) FILTER (WHERE delivery_method = 'carrier' AND repair_successful = TRUE) as carrier_success,
            count(*) FILTER (WHERE delivery_method = 'carrier' AND repair_successful = FALSE) as carrier_fail,
            count(*) FILTER (WHERE is_outsourced = TRUE) as outsourced_total,
            count(*) FILTER (WHERE is_outsourced = TRUE AND repair_successful = TRUE) as outsourced_success,
            count(*) FILTER (WHERE is_outsourced = TRUE AND repair_successful = FALSE) as outsourced_fail,
            sum(COALESCE(outsourced_return_count, 0)) as outsourced_returns,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto')) as internal_total,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto') AND repair_successful = TRUE) as internal_success,
            count(*) FILTER (WHERE is_outsourced = FALSE AND (technician_id IS NOT NULL OR status <> 'Aberto') AND repair_successful = FALSE) as internal_fail
        FROM filtered_tickets
    ),
    top_defects AS (
        SELECT defect_name as label, count(*) as total, count(*) FILTER (WHERE repair_successful = TRUE) as success, count(*) FILTER (WHERE repair_successful = FALSE) as fail, CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate", CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate" FROM expanded_defects GROUP BY defect_name ORDER BY total DESC
    ),
    top_models AS (
        SELECT device_model as label, count(*) as total, count(*) FILTER (WHERE repair_successful = TRUE) as success, count(*) FILTER (WHERE repair_successful = FALSE) as fail, CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate", CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate" FROM filtered_tickets WHERE device_model IS NOT NULL GROUP BY device_model ORDER BY total DESC
    ),
    top_combos AS (
        SELECT device_model || ' · ' || defect_name as label, count(*) as total, count(*) FILTER (WHERE repair_successful = TRUE) as success, count(*) FILTER (WHERE repair_successful = FALSE) as fail, CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = TRUE)::numeric / count(*)) * 100) ELSE 0 END as "successRate", CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE repair_successful = FALSE)::numeric / count(*)) * 100) ELSE 0 END as "failRate" FROM expanded_defects WHERE device_model IS NOT NULL GROUP BY device_model, defect_name ORDER BY total DESC
    ),
    tech_metrics AS (
        SELECT t.technician_id, count(*) as total, count(*) FILTER (WHERE t.repair_successful IS NOT NULL) as completed, count(*) FILTER (WHERE t.repair_successful = TRUE) as success_count FROM filtered_tickets t WHERE t.technician_id IS NOT NULL GROUP BY t.technician_id
    )
    SELECT
        jsonb_build_object(
            'successRate', CASE WHEN (SELECT total_with_outcome FROM stats) > 0 THEN round(((SELECT success_count FROM stats)::numeric / (SELECT total_with_outcome FROM stats)) * 100) ELSE 0 END,
            'avgRepair', COALESCE((SELECT avg_repair_sec FROM stats) * 1000, 0),
            'avgSolution', COALESCE((SELECT avg_solution_sec FROM stats) * 1000, 0),
            'avgDelivery', COALESCE((SELECT avg_delivery_sec FROM stats) * 1000, 0),
            'avgBudget', COALESCE((SELECT avg_budget_sec FROM stats) * 1000, 0),
            'avgPickupNotify', COALESCE((SELECT avg_pickup_notify_sec FROM stats) * 1000, 0),
            'analysisCount', (SELECT analysis_count FROM stats),
            'repairCount', (SELECT repair_count FROM stats),
            
'ticketsPerDay', CASE
  WHEN (SELECT total_tickets FROM stats) = 0 THEN 0
  ELSE (
    WITH period AS (
      SELECT
        COALESCE(
          p_date_start,
          (SELECT MIN((created_at AT TIME ZONE 'America/Sao_Paulo')::date) FROM filtered_tickets)
        ) AS d_start,
        COALESCE(
          p_date_end,
          (now() AT TIME ZONE 'America/Sao_Paulo')::date
        ) AS d_end
    )
    SELECT CASE
      WHEN d_start IS NULL THEN 0
      WHEN d_end < d_start THEN 0
      ELSE ROUND(
        (SELECT total_tickets FROM stats)::numeric
        / NULLIF((d_end - d_start + 1), 0),
        2
      )
    END
    FROM period
  )
END,
            'repairsToday', (SELECT repairs_today FROM stats),
            'repairsWeek', (SELECT repairs_week FROM stats),
            'repairsMonth', (SELECT repairs_month FROM stats),
            'ticketsToday', (SELECT tickets_today FROM stats),
            'ticketsWeek', (SELECT tickets_week FROM stats),
            'ticketsMonth', (SELECT tickets_month FROM stats),
            'topDefects', (SELECT COALESCE(jsonb_agg(d), '[]'::jsonb) FROM (SELECT * FROM top_defects) d),
            'topModels', (SELECT COALESCE(jsonb_agg(m), '[]'::jsonb) FROM (SELECT * FROM top_models LIMIT 100) m),
            'topCombos', (SELECT COALESCE(jsonb_agg(c), '[]'::jsonb) FROM (SELECT * FROM top_combos LIMIT 50) c),
            'techStats', (SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (SELECT tm.technician_id as id, e.name, tm.total, tm.completed, CASE WHEN tm.completed > 0 THEN round((tm.success_count::numeric / tm.completed) * 100) ELSE 0 END as "successRate" FROM tech_metrics tm LEFT JOIN public.employees e ON e.id = tm.technician_id ORDER BY tm.completed DESC) t),
            'slowestModels', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count FROM filtered_tickets WHERE duration_repair_sec > 0 GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestModelsSolution', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model as label, avg(duration_solution_sec) * 1000 as "avgTime", count(*) as count FROM filtered_tickets WHERE duration_solution_sec > 0 GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestModelsDelivery', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model as label, avg(duration_delivery_sec) * 1000 as "avgTime", count(*) as count FROM filtered_tickets WHERE duration_delivery_sec > 0 GROUP BY device_model ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestDefects', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT defect_name as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count FROM expanded_defects WHERE duration_repair_sec > 0 GROUP BY defect_name ORDER BY "avgTime" DESC LIMIT 5) x),
            'slowestCombos', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (SELECT device_model || ' - ' || defect_name as label, avg(duration_repair_sec) * 1000 as "avgTime", count(*) as count FROM expanded_defects WHERE duration_repair_sec > 0 GROUP BY label ORDER BY "avgTime" DESC LIMIT 5) x),
            'logisticsStats', jsonb_build_object('pickup', jsonb_build_object('total', (SELECT pickup_total FROM stats), 'success', (SELECT pickup_success FROM stats), 'fail', (SELECT pickup_fail FROM stats)), 'carrier', jsonb_build_object('total', (SELECT carrier_total FROM stats), 'success', (SELECT carrier_success FROM stats), 'fail', (SELECT carrier_fail FROM stats))),
            'outsourcedStats', jsonb_build_object('total', (SELECT outsourced_total FROM stats), 'success', (SELECT outsourced_success FROM stats), 'fail', (SELECT outsourced_fail FROM stats), 'returns', (SELECT outsourced_returns FROM stats)),
            'internalStats', jsonb_build_object('total', (SELECT internal_total FROM stats), 'success', (SELECT internal_success FROM stats), 'fail', (SELECT internal_fail FROM stats))
        ) INTO v_result;

    RETURN v_result;
END;
$function$;
CREATE OR REPLACE FUNCTION public.get_daily_report(p_date_start text DEFAULT NULL::text, p_date_end text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_workspace_id uuid;
    v_user_id uuid;
    v_start timestamp;
    v_end timestamp;
    v_result jsonb;
begin
    SELECT ctx.workspace_id INTO v_workspace_id FROM public.get_current_actor_context() ctx;
    IF NOT public.can_manage_workspace(v_workspace_id) THEN RAISE EXCEPTION 'Permissao negada ao relatorio gerencial.' USING ERRCODE='42501'; END IF;

    if p_date_start is null or p_date_start = '' then
        v_start := current_date::timestamp;
    else
        v_start := (p_date_start || ' 00:00:00')::timestamp;
    end if;

    if p_date_end is null or p_date_end = '' then
        v_end := (current_date || ' 23:59:59')::timestamp;
    else
        v_end := (p_date_end || ' 23:59:59')::timestamp;
    end if;

    select jsonb_build_object(
        'counts', (
            select jsonb_build_object(
                'created', (select count(*) from tickets where workspace_id = v_workspace_id and created_at between v_start and v_end),
                'repair_success', (select count(*) from tickets where workspace_id = v_workspace_id and repair_end_at between v_start and v_end and repair_successful = true),
                'repair_fail', (select count(*) from tickets where workspace_id = v_workspace_id and repair_end_at between v_start and v_end and repair_successful = false),
                'budget_sent', (select count(*) from tickets where workspace_id = v_workspace_id and budget_sent_at between v_start and v_end),
                'budget_approved', (select count(*) from ticket_logs l join tickets t on l.ticket_id = t.id where t.workspace_id = v_workspace_id and l.action = 'Aprovou Orçamento' and l.created_at between v_start and v_end),
                'budget_rejected', (select count(*) from ticket_logs l join tickets t on l.ticket_id = t.id where t.workspace_id = v_workspace_id and l.action = 'Negou Orçamento' and l.created_at between v_start and v_end),
                'test_approved', (select count(*) from ticket_logs l join tickets t on l.ticket_id = t.id where t.workspace_id = v_workspace_id and l.action = 'Concluiu Testes' and l.created_at between v_start and v_end),
                'test_rejected', (select count(*) from ticket_logs l join tickets t on l.ticket_id = t.id where t.workspace_id = v_workspace_id and l.action = 'Reprovou Testes' and l.created_at between v_start and v_end),
                'outsourced_sent', (select count(*) from ticket_logs l join tickets t on l.ticket_id = t.id where t.workspace_id = v_workspace_id and l.action = 'Enviou Terceirizado' and l.created_at between v_start and v_end)
            )
        ),
        'lists', (
            select jsonb_build_object(
                'arrivals', (
                    select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    from (
                        select id, client_name, device_model, os_number, created_at, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        from tickets
                        where workspace_id = v_workspace_id and created_at between v_start and v_end
                        order by created_at desc
                    ) t
                ),
                'delivered', (
                    select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    from (
                        select id, client_name, device_model, os_number, delivered_at, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        from tickets
                        where workspace_id = v_workspace_id and delivered_at between v_start and v_end
                        order by delivered_at desc
                    ) t
                ),
                'overdue_analysis', (
                    select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    from (
                        select id, client_name, device_model, os_number, analysis_deadline, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        from tickets
                        where workspace_id = v_workspace_id
                          and status = 'Analise Tecnica'
                          and analysis_deadline < now()
                        order by analysis_deadline asc
                    ) t
                ),
                'overdue_repair', (
                    select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
                    from (
                        select id, client_name, device_model, os_number, deadline, status, is_outsourced, budget_status, parts_status, repair_start_at, test_start_at, pickup_available, delivery_method, tracking_code, outsourced_deadline, outsourced_company_id, analysis_started_at
                        from tickets
                        where workspace_id = v_workspace_id
                          and status = 'Andamento Reparo'
                          and deadline < now()
                        order by deadline asc
                    ) t
                ),
                'technicians', (
                    select coalesce(jsonb_agg(row_to_json(stat)), '[]'::jsonb)
                    from (
                        select
                            e.name as name,
                            count(*) filter (where t.repair_successful = true) as success,
                            count(*) filter (where t.repair_successful = false) as fail,
                            case
                                when count(*) > 0 then round((count(*) filter (where t.repair_successful = true)::numeric / count(*)::numeric) * 100, 1)
                                else 0
                            end as rate
                        from employees e
                        join tickets t on t.technician_id = e.id
                        where e.workspace_id = v_workspace_id
                          and t.repair_end_at between v_start and v_end
                          and e.roles::text ilike '%tecnico%'
                        group by e.id, e.name
                    ) stat
                )
            )
        )
    ) into v_result;

    return v_result;
end;
$function$;
CREATE OR REPLACE FUNCTION public.get_operational_queue(p_window text, p_basis text, p_status text DEFAULT NULL::text, p_technician_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 200, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_workspace_id uuid;
    v_user_id uuid;
    v_tz text := 'America/Sao_Paulo';
    v_today_date date;
    v_today_start timestamptz;
    v_tomorrow_start timestamptz;
    v_day_after_tomorrow_start timestamptz;
    v_in_8_days_start timestamptz;
    v_counts jsonb;
    v_status_counts jsonb;
    v_items jsonb;
    v_queues jsonb;
BEGIN
    IF p_window NOT IN ('today', 'today_tomorrow', 'next_7_days', 'overdue', 'no_deadline', 'all') THEN
        RAISE EXCEPTION 'Parâmetro p_window inválido.';
    END IF;

    IF p_basis NOT IN ('auto', 'analysis', 'delivery', 'entry', 'outsourced') THEN
        RAISE EXCEPTION 'Parâmetro p_basis inválido.';
    END IF;

    IF p_limit < 0 OR p_limit > 200 THEN
        RAISE EXCEPTION 'Parâmetro p_limit deve estar entre 0 e 200.';
    END IF;

    IF p_offset < 0 THEN
        RAISE EXCEPTION 'Parâmetro p_offset não pode ser negativo.';
    END IF;

    SELECT ctx.workspace_id INTO v_workspace_id FROM public.get_current_actor_context() ctx;

    v_today_date := (now() AT TIME ZONE v_tz)::date;
    v_today_start := v_today_date::timestamp AT TIME ZONE v_tz;
    v_tomorrow_start := v_today_start + interval '1 day';
    v_day_after_tomorrow_start := v_today_start + interval '2 days';
    v_in_8_days_start := v_today_start + interval '8 days';

    WITH base_tickets AS (
        SELECT
            t.*,
            CASE
                WHEN p_basis = 'analysis' THEN t.analysis_deadline
                WHEN p_basis = 'delivery' THEN t.deadline
                WHEN p_basis = 'entry' THEN t.entry_date
                WHEN p_basis = 'outsourced' THEN t.outsourced_deadline
                WHEN p_basis = 'auto' THEN
                    CASE
                        WHEN t.status = 'Terceirizado' AND t.outsourced_deadline IS NOT NULL THEN t.outsourced_deadline
                        WHEN t.status IN ('Aberto', 'Analise Tecnica') AND t.analysis_deadline IS NOT NULL THEN t.analysis_deadline
                        WHEN t.status IN ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente') AND t.deadline IS NOT NULL THEN t.deadline
                        ELSE COALESCE(t.analysis_deadline, t.deadline, t.outsourced_deadline)
                    END
            END AS effective_due_at,
            CASE
                WHEN p_basis = 'analysis' AND t.analysis_deadline IS NOT NULL THEN 'analysis'
                WHEN p_basis = 'delivery' AND t.deadline IS NOT NULL THEN 'delivery'
                WHEN p_basis = 'entry' AND t.entry_date IS NOT NULL THEN 'entry'
                WHEN p_basis = 'outsourced' AND t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                WHEN p_basis = 'auto' THEN
                    CASE
                        WHEN t.status = 'Terceirizado' AND t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                        WHEN t.status IN ('Aberto', 'Analise Tecnica') AND t.analysis_deadline IS NOT NULL THEN 'analysis'
                        WHEN t.status IN ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente') AND t.deadline IS NOT NULL THEN 'delivery'
                        WHEN t.analysis_deadline IS NOT NULL THEN 'analysis'
                        WHEN t.deadline IS NOT NULL THEN 'delivery'
                        WHEN t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                        ELSE 'none'
                    END
                ELSE 'none'
            END AS effective_due_type
        FROM public.tickets t
        WHERE t.workspace_id = v_workspace_id
          AND t.deleted_at IS NULL
          AND (
              (p_status IS NULL AND t.status <> 'Finalizado')
              OR (p_status = 'all' AND t.status <> 'Finalizado')
              OR (p_status IS NOT NULL AND p_status <> 'all' AND t.status = p_status)
          )
          AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
          AND (
              p_search IS NULL OR p_search = ''
              OR t.client_name ILIKE '%' || p_search || '%'
              OR t.os_number ILIKE '%' || p_search || '%'
              OR t.device_model ILIKE '%' || p_search || '%'
              OR t.serial_number ILIKE '%' || p_search || '%'
              OR t.contact_info ILIKE '%' || p_search || '%'
          )
    ),
    bucketed_tickets AS (
        SELECT
            bt.*,
            CASE
                WHEN bt.effective_due_at IS NULL THEN 'no_deadline'
                WHEN bt.effective_due_at < v_today_start THEN 'overdue'
                WHEN bt.effective_due_at < v_tomorrow_start THEN 'today'
                WHEN bt.effective_due_at < v_day_after_tomorrow_start THEN 'tomorrow'
                WHEN bt.effective_due_at < v_in_8_days_start THEN 'next_7_days'
                ELSE 'later'
            END AS urgency_bucket,
            COALESCE(bt.effective_due_at < v_today_start, false) AS is_overdue,
            CASE
                WHEN bt.effective_due_at IS NOT NULL THEN
                    (bt.effective_due_at AT TIME ZONE v_tz)::date - (v_today_start AT TIME ZONE v_tz)::date
                ELSE NULL
            END AS days_to_due
        FROM base_tickets bt
    ),
    windowed_tickets AS (
        SELECT *
        FROM bucketed_tickets ft
        WHERE p_window = 'all'
           OR (p_window = 'overdue' AND ft.urgency_bucket = 'overdue')
           OR (p_window = 'no_deadline' AND ft.urgency_bucket = 'no_deadline')
           OR (p_window = 'today' AND ft.urgency_bucket = 'today')
           OR (p_window = 'today_tomorrow' AND ft.urgency_bucket IN ('today', 'tomorrow'))
           OR (p_window = 'next_7_days' AND ft.urgency_bucket IN ('today', 'tomorrow', 'next_7_days'))
    ),
    aggregated_counts AS (
        SELECT jsonb_build_object(
            'today', count(*) FILTER (WHERE urgency_bucket = 'today'),
            'today_tomorrow', count(*) FILTER (WHERE urgency_bucket IN ('today', 'tomorrow')),
            'next_7_days', count(*) FILTER (WHERE urgency_bucket IN ('today', 'tomorrow', 'next_7_days')),
            'overdue', count(*) FILTER (WHERE urgency_bucket = 'overdue'),
            'no_deadline', count(*) FILTER (WHERE urgency_bucket = 'no_deadline'),
            'all', count(*)
        ) AS counts
        FROM bucketed_tickets
    ),
    status_counts AS (
        SELECT jsonb_build_object(
            'open', count(*),
            'analysis', count(*) FILTER (WHERE status = 'Analise Tecnica'),
            'approval', count(*) FILTER (WHERE status = 'Aprovacao'),
            'pickup', count(*) FILTER (WHERE status = 'Retirada Cliente')
        ) AS counts
        FROM bucketed_tickets
    ),
    filtered_items AS (
        SELECT COALESCE(jsonb_agg(row_to_json(filtered.*)), '[]'::jsonb) AS items
        FROM (
            SELECT *
            FROM windowed_tickets ft
            ORDER BY
                ft.effective_due_at ASC NULLS LAST,
                ft.priority_requested DESC NULLS LAST,
                CASE ft.priority
                    WHEN 'Urgente' THEN 1
                    WHEN 'Alta' THEN 2
                    WHEN 'Normal' THEN 3
                    WHEN 'Baixa' THEN 4
                    ELSE 5
                END,
                ft.created_at,
                ft.id
            LIMIT p_limit OFFSET p_offset
        ) filtered
    ),
    module_rows AS (
        SELECT
            wt.*,
            CASE wt.overview_queue_stage
                WHEN 'budget_send_pending' THEN 'pendingBudgets'
                WHEN 'budget_approval_pending' THEN 'waitingBudgetResponse'
                WHEN 'pickup_pending' THEN 'pendingPickups'
                WHEN 'tracking_pending' THEN 'pendingTracking'
                WHEN 'delivery_pending' THEN 'pendingDelivery'
                WHEN 'analysis_start_pending' THEN 'pendingTech'
                WHEN 'outsourced_to_send' THEN 'outsourcedToSend'
                WHEN 'outsourced_waiting_return' THEN 'pendingOutsourced'
                WHEN 'parts_purchase_pending' THEN 'pendingPurchase'
                WHEN 'parts_receipt_pending' THEN 'pendingReceipt'
            END AS queue_key
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.overview_queue_stage IN (
              'budget_send_pending', 'budget_approval_pending', 'pickup_pending',
              'tracking_pending', 'delivery_pending', 'analysis_start_pending',
              'outsourced_to_send', 'outsourced_waiting_return',
              'parts_purchase_pending', 'parts_receipt_pending'
          )
    ),
    attention_rows AS (
        SELECT wt.*, 'priorityTickets'::text AS queue_key
        FROM windowed_tickets wt
        WHERE p_limit = 0 AND COALESCE(wt.priority_requested, false)

        UNION ALL
        SELECT wt.*, 'expiringDeliveries'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'delivery'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredDeliveries'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'delivery'
          AND wt.is_overdue

        UNION ALL
        SELECT wt.*, 'expiringAnalysis'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'analysis'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredAnalysis'::text
        FROM windowed_tickets wt
        WHERE p_limit = 0
          AND wt.effective_due_type = 'analysis'
          AND wt.is_overdue
    ),
    queue_rows AS (
        SELECT * FROM module_rows
        UNION ALL
        SELECT * FROM attention_rows
    ),
    ranked_queues AS (
        SELECT
            qr.*,
            CASE
                WHEN COALESCE(qr.priority_requested, false) THEN 0
                WHEN qr.priority = 'Urgente' THEN 1
                WHEN qr.priority = 'Alta' THEN 2
                WHEN qr.priority = 'Normal' THEN 3
                WHEN qr.priority = 'Baixa' THEN 4
                ELSE 5
            END AS queue_priority_rank,
            COALESCE(qr.effective_due_at, 'infinity'::timestamptz) AS queue_due_sort,
            COALESCE(qr.overview_queue_entered_at, qr.updated_at, qr.created_at, qr.entry_date, 'infinity'::timestamptz) AS queue_entered_sort,
            row_number() OVER (
                PARTITION BY qr.queue_key
                ORDER BY
                    CASE
                        WHEN COALESCE(qr.priority_requested, false) THEN 0
                        WHEN qr.priority = 'Urgente' THEN 1
                        WHEN qr.priority = 'Alta' THEN 2
                        WHEN qr.priority = 'Normal' THEN 3
                        WHEN qr.priority = 'Baixa' THEN 4
                        ELSE 5
                    END,
                    COALESCE(qr.effective_due_at, 'infinity'::timestamptz),
                    COALESCE(qr.overview_queue_entered_at, qr.updated_at, qr.created_at, qr.entry_date, 'infinity'::timestamptz),
                    qr.created_at,
                    qr.id
            ) AS queue_row_number
        FROM queue_rows qr
    ),
    queue_rollup AS (
        SELECT
            queue_key,
            count(*) AS total,
            COALESCE(
                jsonb_agg(
                    to_jsonb(rq)
                    - 'queue_key'
                    - 'queue_priority_rank'
                    - 'queue_due_sort'
                    - 'queue_entered_sort'
                    - 'queue_row_number'
                    ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
                ) FILTER (WHERE queue_row_number <= 5),
                '[]'::jsonb
            ) AS items
        FROM ranked_queues rq
        GROUP BY queue_key
    ),
    queue_summary AS (
        SELECT COALESCE(
            jsonb_object_agg(
                queue_key,
                jsonb_build_object('total', total, 'items', items)
            ),
            '{}'::jsonb
        ) AS queues
        FROM queue_rollup
    )
    SELECT
        (SELECT counts FROM aggregated_counts),
        (SELECT counts FROM status_counts),
        (SELECT items FROM filtered_items),
        (SELECT queues FROM queue_summary)
    INTO v_counts, v_status_counts, v_items, v_queues;

    RETURN jsonb_build_object(
        'counts', COALESCE(v_counts, '{}'::jsonb),
        'status_counts', COALESCE(v_status_counts, '{}'::jsonb),
        'items', COALESCE(v_items, '[]'::jsonb),
        'queues', COALESCE(v_queues, '{}'::jsonb)
    );
END;
$function$;
CREATE OR REPLACE FUNCTION public.get_overview_queue_page(p_queue_key text, p_window text DEFAULT 'all'::text, p_basis text DEFAULT 'auto'::text, p_status text DEFAULT NULL::text, p_technician_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_workspace_id uuid;
    v_user_id uuid;
    v_tz text := 'America/Sao_Paulo';
    v_today_date date;
    v_today_start timestamptz;
    v_tomorrow_start timestamptz;
    v_day_after_tomorrow_start timestamptz;
    v_in_8_days_start timestamptz;
    v_total bigint;
    v_items jsonb;
    v_has_more boolean;
    v_next_cursor jsonb;
BEGIN
    IF p_queue_key NOT IN (
        'pendingBudgets', 'waitingBudgetResponse', 'pendingPickups',
        'pendingTracking', 'pendingDelivery', 'pendingTech',
        'outsourcedToSend', 'pendingOutsourced', 'pendingPurchase',
        'pendingReceipt', 'priorityTickets', 'expiringDeliveries',
        'expiredDeliveries', 'expiringAnalysis', 'expiredAnalysis'
    ) THEN
        RAISE EXCEPTION 'Fila da Visão Geral inválida.';
    END IF;

    IF p_window NOT IN ('today', 'today_tomorrow', 'next_7_days', 'overdue', 'no_deadline', 'all') THEN
        RAISE EXCEPTION 'Parâmetro p_window inválido.';
    END IF;

    IF p_basis NOT IN ('auto', 'analysis', 'delivery', 'entry', 'outsourced') THEN
        RAISE EXCEPTION 'Parâmetro p_basis inválido.';
    END IF;

    IF p_limit < 1 OR p_limit > 50 THEN
        RAISE EXCEPTION 'Parâmetro p_limit deve estar entre 1 e 50.';
    END IF;

    IF p_cursor IS NOT NULL
       AND NOT (p_cursor ?& ARRAY['priority_rank', 'due_sort', 'entered_sort', 'created_at', 'id']) THEN
        RAISE EXCEPTION 'Cursor de paginação inválido.';
    END IF;

    SELECT ctx.workspace_id INTO v_workspace_id FROM public.get_current_actor_context() ctx;

    v_today_date := (now() AT TIME ZONE v_tz)::date;
    v_today_start := v_today_date::timestamp AT TIME ZONE v_tz;
    v_tomorrow_start := v_today_start + interval '1 day';
    v_day_after_tomorrow_start := v_today_start + interval '2 days';
    v_in_8_days_start := v_today_start + interval '8 days';

    WITH base_tickets AS (
        SELECT
            t.*,
            CASE
                WHEN p_basis = 'analysis' THEN t.analysis_deadline
                WHEN p_basis = 'delivery' THEN t.deadline
                WHEN p_basis = 'entry' THEN t.entry_date
                WHEN p_basis = 'outsourced' THEN t.outsourced_deadline
                WHEN p_basis = 'auto' THEN
                    CASE
                        WHEN t.status = 'Terceirizado' AND t.outsourced_deadline IS NOT NULL THEN t.outsourced_deadline
                        WHEN t.status IN ('Aberto', 'Analise Tecnica') AND t.analysis_deadline IS NOT NULL THEN t.analysis_deadline
                        WHEN t.status IN ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente') AND t.deadline IS NOT NULL THEN t.deadline
                        ELSE COALESCE(t.analysis_deadline, t.deadline, t.outsourced_deadline)
                    END
            END AS effective_due_at,
            CASE
                WHEN p_basis = 'analysis' AND t.analysis_deadline IS NOT NULL THEN 'analysis'
                WHEN p_basis = 'delivery' AND t.deadline IS NOT NULL THEN 'delivery'
                WHEN p_basis = 'entry' AND t.entry_date IS NOT NULL THEN 'entry'
                WHEN p_basis = 'outsourced' AND t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                WHEN p_basis = 'auto' THEN
                    CASE
                        WHEN t.status = 'Terceirizado' AND t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                        WHEN t.status IN ('Aberto', 'Analise Tecnica') AND t.analysis_deadline IS NOT NULL THEN 'analysis'
                        WHEN t.status IN ('Aprovacao', 'Compra Peca', 'Andamento Reparo', 'Teste Final', 'Retirada Cliente') AND t.deadline IS NOT NULL THEN 'delivery'
                        WHEN t.analysis_deadline IS NOT NULL THEN 'analysis'
                        WHEN t.deadline IS NOT NULL THEN 'delivery'
                        WHEN t.outsourced_deadline IS NOT NULL THEN 'outsourced'
                        ELSE 'none'
                    END
                ELSE 'none'
            END AS effective_due_type
        FROM public.tickets t
        WHERE t.workspace_id = v_workspace_id
          AND t.deleted_at IS NULL
          AND (
              (p_status IS NULL AND t.status <> 'Finalizado')
              OR (p_status = 'all' AND t.status <> 'Finalizado')
              OR (p_status IS NOT NULL AND p_status <> 'all' AND t.status = p_status)
          )
          AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
          AND (
              p_search IS NULL OR p_search = ''
              OR t.client_name ILIKE '%' || p_search || '%'
              OR t.os_number ILIKE '%' || p_search || '%'
              OR t.device_model ILIKE '%' || p_search || '%'
              OR t.serial_number ILIKE '%' || p_search || '%'
              OR t.contact_info ILIKE '%' || p_search || '%'
          )
    ),
    bucketed_tickets AS (
        SELECT
            bt.*,
            CASE
                WHEN bt.effective_due_at IS NULL THEN 'no_deadline'
                WHEN bt.effective_due_at < v_today_start THEN 'overdue'
                WHEN bt.effective_due_at < v_tomorrow_start THEN 'today'
                WHEN bt.effective_due_at < v_day_after_tomorrow_start THEN 'tomorrow'
                WHEN bt.effective_due_at < v_in_8_days_start THEN 'next_7_days'
                ELSE 'later'
            END AS urgency_bucket,
            COALESCE(bt.effective_due_at < v_today_start, false) AS is_overdue,
            CASE
                WHEN bt.effective_due_at IS NOT NULL THEN
                    (bt.effective_due_at AT TIME ZONE v_tz)::date - (v_today_start AT TIME ZONE v_tz)::date
                ELSE NULL
            END AS days_to_due
        FROM base_tickets bt
    ),
    windowed_tickets AS (
        SELECT *
        FROM bucketed_tickets ft
        WHERE p_window = 'all'
           OR (p_window = 'overdue' AND ft.urgency_bucket = 'overdue')
           OR (p_window = 'no_deadline' AND ft.urgency_bucket = 'no_deadline')
           OR (p_window = 'today' AND ft.urgency_bucket = 'today')
           OR (p_window = 'today_tomorrow' AND ft.urgency_bucket IN ('today', 'tomorrow'))
           OR (p_window = 'next_7_days' AND ft.urgency_bucket IN ('today', 'tomorrow', 'next_7_days'))
    ),
    module_rows AS (
        SELECT
            wt.*,
            CASE wt.overview_queue_stage
                WHEN 'budget_send_pending' THEN 'pendingBudgets'
                WHEN 'budget_approval_pending' THEN 'waitingBudgetResponse'
                WHEN 'pickup_pending' THEN 'pendingPickups'
                WHEN 'tracking_pending' THEN 'pendingTracking'
                WHEN 'delivery_pending' THEN 'pendingDelivery'
                WHEN 'analysis_start_pending' THEN 'pendingTech'
                WHEN 'outsourced_to_send' THEN 'outsourcedToSend'
                WHEN 'outsourced_waiting_return' THEN 'pendingOutsourced'
                WHEN 'parts_purchase_pending' THEN 'pendingPurchase'
                WHEN 'parts_receipt_pending' THEN 'pendingReceipt'
            END AS queue_key
        FROM windowed_tickets wt
        WHERE wt.overview_queue_stage IN (
            'budget_send_pending', 'budget_approval_pending', 'pickup_pending',
            'tracking_pending', 'delivery_pending', 'analysis_start_pending',
            'outsourced_to_send', 'outsourced_waiting_return',
            'parts_purchase_pending', 'parts_receipt_pending'
        )
    ),
    attention_rows AS (
        SELECT wt.*, 'priorityTickets'::text AS queue_key
        FROM windowed_tickets wt
        WHERE COALESCE(wt.priority_requested, false)

        UNION ALL
        SELECT wt.*, 'expiringDeliveries'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'delivery'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredDeliveries'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'delivery'
          AND wt.is_overdue

        UNION ALL
        SELECT wt.*, 'expiringAnalysis'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'analysis'
          AND NOT wt.is_overdue
          AND wt.urgency_bucket IN ('today', 'tomorrow')

        UNION ALL
        SELECT wt.*, 'expiredAnalysis'::text
        FROM windowed_tickets wt
        WHERE wt.effective_due_type = 'analysis'
          AND wt.is_overdue
    ),
    queue_rows AS (
        SELECT * FROM module_rows
        UNION ALL
        SELECT * FROM attention_rows
    ),
    ordered_rows AS (
        SELECT
            qr.*,
            CASE
                WHEN COALESCE(qr.priority_requested, false) THEN 0
                WHEN qr.priority = 'Urgente' THEN 1
                WHEN qr.priority = 'Alta' THEN 2
                WHEN qr.priority = 'Normal' THEN 3
                WHEN qr.priority = 'Baixa' THEN 4
                ELSE 5
            END AS queue_priority_rank,
            COALESCE(qr.effective_due_at, 'infinity'::timestamptz) AS queue_due_sort,
            COALESCE(qr.overview_queue_entered_at, qr.updated_at, qr.created_at, qr.entry_date, 'infinity'::timestamptz) AS queue_entered_sort
        FROM queue_rows qr
        WHERE qr.queue_key = p_queue_key
    ),
    after_cursor AS (
        SELECT *
        FROM ordered_rows oq
        WHERE p_cursor IS NULL
           OR (
                oq.queue_priority_rank,
                oq.queue_due_sort,
                oq.queue_entered_sort,
                oq.created_at,
                oq.id
              ) > (
                (p_cursor->>'priority_rank')::integer,
                (p_cursor->>'due_sort')::timestamptz,
                (p_cursor->>'entered_sort')::timestamptz,
                (p_cursor->>'created_at')::timestamptz,
                (p_cursor->>'id')::uuid
              )
    ),
    page_plus_one AS (
        SELECT *
        FROM after_cursor
        ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
        LIMIT p_limit + 1
    ),
    page_rows AS (
        SELECT *
        FROM page_plus_one
        ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
        LIMIT p_limit
    )
    SELECT
        (SELECT count(*) FROM ordered_rows),
        COALESCE((
            SELECT jsonb_agg(
                to_jsonb(pr)
                - 'queue_key'
                - 'queue_priority_rank'
                - 'queue_due_sort'
                - 'queue_entered_sort'
                ORDER BY queue_priority_rank, queue_due_sort, queue_entered_sort, created_at, id
            )
            FROM page_rows pr
        ), '[]'::jsonb),
        (SELECT count(*) > p_limit FROM page_plus_one),
        CASE
            WHEN (SELECT count(*) > p_limit FROM page_plus_one) THEN (
                SELECT jsonb_build_object(
                    'priority_rank', queue_priority_rank,
                    'due_sort', queue_due_sort,
                    'entered_sort', queue_entered_sort,
                    'created_at', created_at,
                    'id', id
                )
                FROM page_rows
                ORDER BY queue_priority_rank DESC, queue_due_sort DESC, queue_entered_sort DESC, created_at DESC, id DESC
                LIMIT 1
            )
            ELSE NULL
        END
    INTO v_total, v_items, v_has_more, v_next_cursor;

    RETURN jsonb_build_object(
        'total', COALESCE(v_total, 0),
        'items', COALESCE(v_items, '[]'::jsonb),
        'has_more', COALESCE(v_has_more, false),
        'next_cursor', v_next_cursor
    );
END;
$function$;
CREATE OR REPLACE FUNCTION private.get_schedule_availability(p_technician_id uuid, p_mode text, p_reference_date date, p_days integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_workspace_id uuid;
  v_settings jsonb;
  v_workdays jsonb;
  v_has_break boolean;
  v_break_start time;
  v_break_end time;
  v_extra_breaks jsonb;
  v_slot_duration integer;
  v_max_concurrent integer;
  v_current_date date;
  v_end_date date;
  v_dow integer;
  v_day_config jsonb;
  v_is_active boolean;
  v_start_time time;
  v_end_time time;
  v_slots jsonb[];
  v_days jsonb[] := ARRAY[]::jsonb[];
  v_start_ts timestamp with time zone;
  v_end_ts timestamp with time zone;
  v_day_start_ts timestamp with time zone;
  v_day_end_ts timestamp with time zone;
  v_break_start_ts timestamp with time zone;
  v_break_end_ts timestamp with time zone;
  v_slot_end_ts timestamp with time zone;
  v_appointments jsonb[];
  v_booked integer;
  v_status text;
  
  v_block_id uuid;
  v_block_notes text;
  
  v_eb jsonb;
  v_eb_is_active boolean;
  v_eb_start_time time;
  v_eb_end_time time;
  v_eb_start_ts timestamp with time zone;
  v_eb_end_ts timestamp with time zone;
  v_eb_recurrence_type text;
  v_eb_recurrence_days jsonb;
  v_eb_specific_date date;
  v_eb_matches_day boolean;
  v_slot_in_extra_break boolean;
  
  v_now_ts timestamp with time zone;
BEGIN
  SELECT ctx.workspace_id INTO v_workspace_id FROM public.get_current_actor_context() ctx;

  SELECT settings INTO v_settings FROM technician_schedule_settings WHERE technician_id = p_technician_id;
  
  IF v_settings IS NULL THEN
      v_workdays := '[{"active": false, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": false, "start": "09:00", "end": "12:00"}]'::jsonb;
      v_has_break := true;
      v_break_start := '12:00'::time;
      v_break_end := '13:00'::time;
      v_extra_breaks := '[]'::jsonb;
      v_slot_duration := 30;
      v_max_concurrent := 1;
  ELSE
      v_workdays := v_settings->'workDays';
      v_has_break := (v_settings->>'hasBreak')::boolean;
      v_break_start := (v_settings->>'breakStart')::time;
      v_break_end := (v_settings->>'breakEnd')::time;
      v_extra_breaks := COALESCE(v_settings->'extraBreaks', '[]'::jsonb);
      v_slot_duration := COALESCE((v_settings->>'slotDuration')::integer, 30);
      v_max_concurrent := COALESCE((v_settings->>'maxConcurrent')::integer, 1);
  END IF;

  v_current_date := p_reference_date;
  v_end_date := p_reference_date + p_days - 1;
  
  v_now_ts := NOW();

  WHILE v_current_date <= v_end_date LOOP
      v_dow := EXTRACT(DOW FROM v_current_date);
      v_day_config := v_workdays->v_dow;
      
      v_is_active := (v_day_config->>'active')::boolean;
      v_slots := ARRAY[]::jsonb[];

      IF v_is_active THEN
          v_start_time := (v_day_config->>'start')::time;
          v_end_time := (v_day_config->>'end')::time;

          v_day_start_ts := (v_current_date + v_start_time) AT TIME ZONE 'America/Sao_Paulo';
          v_day_end_ts := (v_current_date + v_end_time) AT TIME ZONE 'America/Sao_Paulo';
          
          IF v_has_break THEN
              v_break_start_ts := (v_current_date + v_break_start) AT TIME ZONE 'America/Sao_Paulo';
              v_break_end_ts := (v_current_date + v_break_end) AT TIME ZONE 'America/Sao_Paulo';
          ELSE
              v_break_start_ts := v_day_start_ts - interval '1 second';
              v_break_end_ts := v_day_start_ts - interval '1 second';
          END IF;

          v_start_ts := v_day_start_ts;
          
          WHILE v_start_ts < v_day_end_ts LOOP
              v_slot_end_ts := v_start_ts + (v_slot_duration || ' minutes')::interval;

              IF v_slot_end_ts > v_day_end_ts THEN
                  EXIT;
              END IF;

              v_slot_in_extra_break := false;
              
              IF jsonb_typeof(v_extra_breaks) = 'array' AND jsonb_array_length(v_extra_breaks) > 0 THEN
                  FOR v_eb IN SELECT * FROM jsonb_array_elements(v_extra_breaks) LOOP
                      v_eb_is_active := (v_eb->>'active')::boolean;
                      IF v_eb_is_active THEN
                          v_eb_start_time := (v_eb->>'start')::time;
                          v_eb_end_time := (v_eb->>'end')::time;
                          v_eb_recurrence_type := v_eb->>'recurrence_type';
                          v_eb_recurrence_days := v_eb->'recurrence_days';
                          
                          v_eb_start_ts := (v_current_date + v_eb_start_time) AT TIME ZONE 'America/Sao_Paulo';
                          v_eb_end_ts := (v_current_date + v_eb_end_time) AT TIME ZONE 'America/Sao_Paulo';
                          
                          v_eb_matches_day := false;
                          
                          IF v_eb_recurrence_type = 'daily' THEN
                              v_eb_matches_day := true;
                          ELSIF v_eb_recurrence_type = 'weekdays' THEN
                              IF EXTRACT(ISODOW FROM v_current_date) BETWEEN 1 AND 5 THEN
                                  v_eb_matches_day := true;
                              END IF;
                          ELSIF v_eb_recurrence_type = 'specific_days' THEN
                              IF v_eb_recurrence_days IS NOT NULL AND v_eb_recurrence_days @> to_jsonb(v_dow) THEN
                                  v_eb_matches_day := true;
                              END IF;
                          ELSIF v_eb_recurrence_type = 'none' THEN
                              IF v_eb->>'specific_date' IS NOT NULL THEN
                                  v_eb_specific_date := (v_eb->>'specific_date')::date;
                                  IF v_current_date = v_eb_specific_date THEN
                                      v_eb_matches_day := true;
                                  END IF;
                              END IF;
                          END IF;

                          IF v_eb_matches_day THEN
                              IF (v_start_ts < v_eb_end_ts AND v_slot_end_ts > v_eb_start_ts) THEN
                                  v_slot_in_extra_break := true;
                                  EXIT;
                              END IF;
                          END IF;
                      END IF;
                  END LOOP;
              END IF;

              IF NOT (v_start_ts >= v_break_start_ts AND v_slot_end_ts <= v_break_end_ts) AND NOT v_slot_in_extra_break THEN
                  
                  v_block_id := NULL;
                  v_block_notes := NULL;

                  IF v_start_ts < v_now_ts THEN
                      v_status := 'passado';
                      v_booked := 0;
                      v_block_notes := 'Horário no passado';
                  ELSE
                      SELECT id, reason INTO v_block_id, v_block_notes
                      FROM technician_schedule_blocks 
                      WHERE technician_id = p_technician_id
                      AND (
                          (block_type = 'full_day' AND DATE(start_at AT TIME ZONE 'America/Sao_Paulo') = v_current_date)
                          OR
                          (block_type = 'time_range' AND start_at < v_slot_end_ts AND end_at > v_start_ts)
                      )
                      LIMIT 1;

                      IF v_block_id IS NOT NULL THEN
                          v_status := 'bloqueado';
                          v_booked := 0;
                      ELSE
                          -- IMPORTANTE: Checagem com overlap (intersecção) em vez de apenas start exato
                          SELECT count(*) INTO v_booked
                          FROM ticket_appointments
                          WHERE technician_id = p_technician_id
                            AND scheduled_start < v_slot_end_ts
                            AND scheduled_end > v_start_ts
                            AND status NOT IN ('completed', 'cancelled')
                            AND deleted_at IS NULL;
                            
                          IF v_booked >= v_max_concurrent THEN
                              v_status := 'lotado';
                          ELSIF v_booked > 0 THEN
                              v_status := 'ocupado';
                          ELSE
                              v_status := 'livre';
                          END IF;
                      END IF;
                  END IF;

                  v_slots := array_append(v_slots, jsonb_build_object(
                      'start', v_start_ts,
                      'end', v_slot_end_ts,
                      'status', v_status,
                      'booked', COALESCE(v_booked, 0),
                      'block_id', v_block_id,
                      'block_notes', v_block_notes
                  ));

              END IF;

              v_start_ts := v_slot_end_ts;
          END LOOP;

      END IF;

      v_days := array_append(v_days, jsonb_build_object(
          'date', v_current_date,
          'capacity', jsonb_build_object('total', array_length(v_slots, 1), 'booked', 0),
          'slots', v_slots
      ));

      v_current_date := v_current_date + interval '1 day';
  END LOOP;

  RETURN jsonb_build_object('days', v_days);
END;
$function$;
CREATE OR REPLACE FUNCTION public.get_employees_for_workspace(p_workspace_id uuid)
 RETURNS TABLE(id uuid, name text, username text, roles text[], created_at timestamp with time zone, workspace_id uuid, is_locked boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
    if not public.can_manage_workspace(p_workspace_id) then
        return;
    end if;

    return query
    select
        e.id,
        e.name,
        e.username,
        e.roles,
        e.created_at,
        e.workspace_id,
        coalesce(s.reset_required, false) as is_locked
    from public.employees e
    left join public.employee_auth_state s
      on e.id = s.employee_id
    where e.workspace_id = p_workspace_id
      and e.deleted_at is null and not e.legacy_auth_disabled
    order by e.created_at desc;
end;
$function$;
CREATE OR REPLACE FUNCTION public.get_employee_security_status(p_workspace_id uuid)
 RETURNS TABLE(employee_id uuid, failed_attempts integer, lock_until timestamp with time zone, reset_required boolean, manual_blocked boolean, manual_blocked_at timestamp with time zone, manual_block_reason text, active_sessions bigint, last_seen_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
    if not public.can_manage_workspace(p_workspace_id) then
        raise exception 'Permissao negada.';
    end if;

    return query
    select e.id,
           coalesce(a.failed_attempts, 0),
           a.lock_until,
           coalesce(a.reset_required, false),
           coalesce(a.manual_blocked, false),
           a.manual_blocked_at,
           a.manual_block_reason,
           count(s.id) filter (
               where s.revoked_at is null
                 and s.expires_at > now()
           ),
           max(s.last_seen_at) filter (where s.revoked_at is null)
    from public.employees e
    left join public.employee_auth_state a on a.employee_id = e.id
    left join public.employee_sessions s on s.employee_id = e.id
    where e.workspace_id = p_workspace_id
      and e.deleted_at is null and not e.legacy_auth_disabled
    group by e.id, a.failed_attempts, a.lock_until, a.reset_required,
             a.manual_blocked, a.manual_blocked_at, a.manual_block_reason
    order by e.name;
end;
$function$;
CREATE OR REPLACE FUNCTION public.update_workspace_company_config(p_whatsapp_number text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor record;
BEGIN
    SELECT * INTO v_actor FROM public.get_current_actor_context();
    PERFORM private.assert_workspace_manager(v_actor.workspace_id);
    IF length(p_whatsapp_number) > 40 THEN RAISE EXCEPTION 'Numero de contato invalido.' USING ERRCODE = '22023'; END IF;
    UPDATE public.workspaces SET whatsapp_number = NULLIF(btrim(p_whatsapp_number), '') WHERE id = v_actor.workspace_id;
END $$;

CREATE OR REPLACE FUNCTION public.can_manage_logo(p_name text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_workspace uuid;
BEGIN
    BEGIN v_workspace := split_part(p_name, '/', 1)::uuid;
    EXCEPTION WHEN invalid_text_representation THEN RETURN false; END;
    RETURN public.can_manage_workspace(v_workspace);
END $$;

CREATE OR REPLACE FUNCTION public.current_employee_from_token()
RETURNS TABLE(employee_id uuid, workspace_id uuid, role text[])
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    SELECT NULL::uuid, NULL::uuid, '{}'::text[] WHERE false;
$$;

CREATE OR REPLACE FUNCTION public.set_current_user_display_name(p_display_name text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_identity record; v_name text := btrim(COALESCE(p_display_name, ''));
BEGIN
    SELECT * INTO v_identity FROM private.auth_identity();
    IF char_length(v_name) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'Nome deve ter entre 2 e 80 caracteres.' USING ERRCODE = '22023'; END IF;
    UPDATE auth.users SET raw_user_meta_data = jsonb_set(COALESCE(raw_user_meta_data, '{}'::jsonb), '{full_name}', to_jsonb(v_name), true), updated_at = now()
    WHERE id = v_identity.user_id;
    RETURN v_name;
END $$;
ALTER FUNCTION public.set_schedule_updated_at() SET search_path = '';

-- Definers share the managed database owner even when tested/deployed by another administrative role.
ALTER TABLE private.auth_workspace_migration_manifest OWNER TO postgres;
ALTER TABLE public.workspace_memberships OWNER TO postgres;
ALTER TABLE public.workspace_invitations OWNER TO postgres;
DO $$ DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS function_name FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE (n.nspname = 'private' AND p.proname IN ('auth_identity','requested_workspace','workspace_actor','has_workspace_permission','assert_workspace_manager','assert_employee_roles','invitation_delivery_details'))
           OR (n.nspname = 'public' AND p.proname IN ('list_my_workspaces','get_my_access_context','create_company_workspace','list_my_pending_invitations',
               'get_my_workspace_invitations','create_workspace_invitation','reissue_workspace_invitation','cancel_workspace_invitation','accept_workspace_invitation',
               'list_workspace_staff','update_employee_access','set_employee_removed','get_invitation_delivery_details','mark_invitation_delivery')) LOOP
        EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.function_name);
    END LOOP;
END $$;

-- Preserve the detailed ticket/customer/note authorization already present; replace the auth transport.
CREATE TEMP TABLE auth_workspace_previous_policies ON COMMIT DROP AS
SELECT * FROM pg_policies WHERE schemaname IN ('public', 'storage');
DO $$ DECLARE r record;
BEGIN
    FOR r IN SELECT schemaname, tablename, policyname FROM auth_workspace_previous_policies LOOP
        EXECUTE format('DROP POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    END LOOP;
    FOR r IN SELECT * FROM auth_workspace_previous_policies WHERE schemaname = 'public'
        AND tablename IN ('tickets', 'ticket_logs', 'internal_notes', 'customers') LOOP
        EXECUTE format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO authenticated%s%s',
            r.policyname, r.schemaname, r.tablename, r.permissive, r.cmd,
            CASE WHEN r.qual IS NULL THEN '' ELSE ' USING (' || r.qual || ')' END,
            CASE WHEN r.with_check IS NULL THEN '' ELSE ' WITH CHECK (' || r.with_check || ')' END);
    END LOOP;
END $$;

CREATE POLICY auth_profiles_self_read ON public.profiles FOR SELECT TO authenticated USING(id = (SELECT auth.uid()));
CREATE POLICY auth_workspace_read ON public.workspaces FOR SELECT TO authenticated USING(private.has_workspace_permission(id, 'member'));
CREATE POLICY auth_employee_directory ON public.employees FOR SELECT TO authenticated
USING(NOT legacy_auth_disabled AND private.has_workspace_permission(workspace_id, 'member')
    AND (deleted_at IS NULL OR private.has_workspace_permission(workspace_id, 'admin')));

DO $$ DECLARE v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['checklist_templates', 'defect_options', 'defects', 'device_models', 'fornecedores', 'suppliers', 'outsourced_companies', 'terceirizados'] LOOP
        EXECUTE format('CREATE POLICY auth_catalog_read ON public.%I FOR SELECT TO authenticated USING(private.has_workspace_permission(workspace_id, ''operational_read''))', v_table);
        EXECUTE format('CREATE POLICY auth_catalog_insert ON public.%I FOR INSERT TO authenticated WITH CHECK(private.has_workspace_permission(workspace_id, ''catalog_write''))', v_table);
        EXECUTE format('CREATE POLICY auth_catalog_update ON public.%I FOR UPDATE TO authenticated USING(private.has_workspace_permission(workspace_id, ''catalog_write'')) WITH CHECK(private.has_workspace_permission(workspace_id, ''catalog_write''))', v_table);
        EXECUTE format('CREATE POLICY auth_catalog_delete ON public.%I FOR DELETE TO authenticated USING(private.has_workspace_permission(workspace_id, ''catalog_write''))', v_table);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', v_table);
    END LOOP;
END $$;

CREATE POLICY auth_notifications_read ON public.notifications FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public.tickets t WHERE t.id = notifications.ticket_id));
CREATE POLICY auth_notifications_insert ON public.notifications FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.tickets t WHERE t.id = notifications.ticket_id));
CREATE POLICY auth_notifications_update ON public.notifications FOR UPDATE TO authenticated
USING(EXISTS(SELECT 1 FROM public.tickets t WHERE t.id = notifications.ticket_id))
WITH CHECK(EXISTS(SELECT 1 FROM public.tickets t WHERE t.id = notifications.ticket_id));
CREATE POLICY auth_notifications_delete ON public.notifications FOR DELETE TO authenticated
USING(EXISTS(SELECT 1 FROM public.tickets t WHERE t.id = notifications.ticket_id AND private.has_workspace_permission(t.workspace_id, 'admin')));

CREATE POLICY auth_schedule_settings_read ON public.technician_schedule_settings FOR SELECT TO authenticated
USING(private.has_workspace_permission(workspace_id, 'member') AND EXISTS(SELECT 1 FROM public.get_current_actor_context() a
    WHERE a.is_admin OR a.is_attendant OR (a.is_technician AND a.actor_employee_id = technician_id)));
CREATE POLICY auth_schedule_settings_insert ON public.technician_schedule_settings FOR INSERT TO authenticated
WITH CHECK(private.has_workspace_permission(workspace_id, 'admin'));
CREATE POLICY auth_schedule_settings_update ON public.technician_schedule_settings FOR UPDATE TO authenticated
USING(private.has_workspace_permission(workspace_id, 'admin')) WITH CHECK(private.has_workspace_permission(workspace_id, 'admin'));
CREATE POLICY auth_schedule_settings_delete ON public.technician_schedule_settings FOR DELETE TO authenticated
USING(private.has_workspace_permission(workspace_id, 'admin'));

CREATE POLICY auth_schedule_blocks_read ON public.technician_schedule_blocks FOR SELECT TO authenticated
USING(private.has_workspace_permission(workspace_id, 'member') AND EXISTS(SELECT 1 FROM public.get_current_actor_context() a
    WHERE a.is_admin OR a.is_attendant OR (a.is_technician AND a.actor_employee_id = technician_id)));
CREATE POLICY auth_appointments_read ON public.ticket_appointments FOR SELECT TO authenticated
USING(private.has_workspace_permission(workspace_id, 'member') AND EXISTS(SELECT 1 FROM public.get_current_actor_context() a
    WHERE a.is_admin OR a.is_attendant OR (a.is_technician AND a.actor_employee_id = technician_id)));

CREATE POLICY auth_logos_public_read ON storage.objects FOR SELECT TO PUBLIC USING(bucket_id = 'workspace_logos');
CREATE POLICY auth_logos_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id = 'workspace_logos' AND public.can_manage_logo(name));
CREATE POLICY auth_logos_update ON storage.objects FOR UPDATE TO authenticated
USING(bucket_id = 'workspace_logos' AND public.can_manage_logo(name))
WITH CHECK(bucket_id = 'workspace_logos' AND public.can_manage_logo(name));
CREATE POLICY auth_logos_delete ON storage.objects FOR DELETE TO authenticated
USING(bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY auth_ticket_photos_read ON storage.objects FOR SELECT TO authenticated
USING(bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND EXISTS(SELECT 1 FROM public.tickets t WHERE t.id::text = (storage.foldername(objects.name))[2]
        AND t.workspace_id = private.requested_workspace()));
CREATE POLICY auth_ticket_photos_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND COALESCE((storage.foldername(name))[2], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND private.has_workspace_permission(private.requested_workspace(), 'ticket_photo_write'));
CREATE POLICY auth_ticket_photos_update ON storage.objects FOR UPDATE TO authenticated
USING(bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND private.has_workspace_permission(private.requested_workspace(), 'ticket_photo_write')
    AND EXISTS(SELECT 1 FROM public.tickets t WHERE t.id::text = (storage.foldername(objects.name))[2]
        AND t.workspace_id = private.requested_workspace()))
WITH CHECK(bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND private.has_workspace_permission(private.requested_workspace(), 'ticket_photo_write')
    AND EXISTS(SELECT 1 FROM public.tickets t WHERE t.id::text = (storage.foldername(objects.name))[2]
        AND t.workspace_id = private.requested_workspace()));
CREATE POLICY auth_ticket_photos_delete ON storage.objects FOR DELETE TO authenticated
USING(bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND private.has_workspace_permission(private.requested_workspace(), 'ticket_photo_write')
    AND EXISTS(SELECT 1 FROM public.tickets t WHERE t.id::text = (storage.foldername(objects.name))[2]
        AND t.workspace_id = private.requested_workspace()));

CREATE POLICY auth_inventory_images_read ON storage.objects FOR SELECT TO authenticated
USING(bucket_id = 'inventory_images' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND private.has_workspace_permission(private.requested_workspace(), 'inventory_read'));
CREATE POLICY auth_inventory_images_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id = 'inventory_images' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND (storage.foldername(name))[2] = 'inventory' AND private.has_workspace_permission(private.requested_workspace(), 'admin'));
CREATE POLICY auth_inventory_images_update ON storage.objects FOR UPDATE TO authenticated
USING(bucket_id = 'inventory_images' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND private.has_workspace_permission(private.requested_workspace(), 'admin'))
WITH CHECK(bucket_id = 'inventory_images' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND (storage.foldername(name))[2] = 'inventory' AND private.has_workspace_permission(private.requested_workspace(), 'admin'));
CREATE POLICY auth_inventory_images_delete ON storage.objects FOR DELETE TO authenticated
USING(bucket_id = 'inventory_images' AND (storage.foldername(name))[1] = private.requested_workspace()::text
    AND private.has_workspace_permission(private.requested_workspace(), 'admin'));

-- Explicit least privilege: no legacy auth RPC, business table or worker RPC is callable anonymously.
DO $$ DECLARE r record;
BEGIN
    FOR r IN SELECT c.oid::regclass AS relation FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind IN ('r','p') LOOP
        EXECUTE format('REVOKE ALL ON TABLE %s FROM anon, PUBLIC', r.relation);
        FOR r IN SELECT c.oid::regclass AS relation, a.attname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_attribute a ON a.attrelid = c.oid WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL LOOP
            EXECUTE format('REVOKE ALL (%I) ON TABLE %s FROM anon, PUBLIC', r.attname, r.relation);
        END LOOP;
    END LOOP;
    FOR r IN SELECT p.oid::regprocedure AS function_name FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, PUBLIC', r.function_name);
    END LOOP;
    FOR r IN SELECT p.oid::regprocedure AS function_name FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'private' AND p.proname IN ('auth_identity','requested_workspace','workspace_actor','has_workspace_permission','assert_workspace_manager','assert_employee_roles','invitation_delivery_details') LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.function_name);
    END LOOP;
END $$;

REVOKE ALL ON public.profiles, public.employees, public.workspaces FROM authenticated;
DO $$ DECLARE r record;
BEGIN
    FOR r IN SELECT c.oid::regclass AS relation, a.attname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid WHERE n.nspname = 'public' AND c.relname IN ('employees','profiles','workspaces')
        AND a.attnum > 0 AND NOT a.attisdropped LOOP
        EXECUTE format('REVOKE ALL (%I) ON TABLE %s FROM authenticated', r.attname, r.relation);
    END LOOP;
END $$;
GRANT SELECT ON public.profiles, public.workspaces TO authenticated;
GRANT SELECT(id, workspace_id, name, username, roles, created_at, deleted_at, legacy_auth_disabled) ON public.employees TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.technician_schedule_settings TO authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_workspace_permission(uuid,text), private.requested_workspace() TO authenticated;

REVOKE ALL ON FUNCTION public.create_employee(uuid,text,text,text,text[]), public.update_employee(uuid,text,text,text,text[]),
    public.employee_login(text,text,text), public.employee_change_password(uuid,text,text), public.employee_logout(uuid),
    public.reset_employee_password(uuid,text), public.validate_employee_session(uuid), public.current_employee_from_token(),
    public.get_workspace_company_config_for_employee(uuid), public.create_owner_workspace_and_profile(text,text)
FROM authenticated;

GRANT EXECUTE ON FUNCTION public.list_my_workspaces(), public.get_my_access_context(uuid), public.create_company_workspace(text),
    public.list_my_pending_invitations(), public.get_my_workspace_invitations(uuid),
    public.create_workspace_invitation(uuid,text,text,text[],uuid), public.reissue_workspace_invitation(uuid),
    public.cancel_workspace_invitation(uuid), public.accept_workspace_invitation(uuid), public.list_workspace_staff(uuid),
    public.update_employee_access(uuid,text,text[]), public.set_employee_account_blocked(uuid,boolean,text),
    public.revoke_employee_sessions(uuid), public.set_employee_removed(uuid,boolean)
TO authenticated;
REVOKE ALL ON FUNCTION public.get_invitation_delivery_details(uuid,uuid), public.mark_invitation_delivery(uuid,uuid,uuid,boolean,text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_invitation_delivery_details(uuid,uuid), public.mark_invitation_delivery(uuid,uuid,uuid,boolean,text) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid,uuid), public.get_client_ticket_details_public_configurable(uuid,uuid) TO anon, authenticated;

COMMIT;

