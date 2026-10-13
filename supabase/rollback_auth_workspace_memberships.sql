-- Restore only this migration in the existing project. Never reset managed schemas.
-- The private manifest contains pre-migration DDL and grants, not application data.
BEGIN;
SET LOCAL search_path = public, pg_catalog;
DO $guard$
BEGIN
    IF to_regclass('private.auth_workspace_migration_manifest') IS NULL THEN
        RAISE EXCEPTION 'Migration receipt missing; aborting rollback.';
    END IF;
END $guard$;

-- Drop policies before restoring functions; some new policies call new helpers.
DO $policies$ DECLARE r record;
BEGIN
    FOR r IN SELECT schemaname, tablename, policyname FROM pg_policies
        WHERE schemaname IN ('public', 'storage') LOOP
        EXECUTE format('DROP POLICY %I ON %I.%I',r.policyname,r.schemaname,r.tablename);
    END LOOP;
END $policies$;

DO $functions$ DECLARE r record;
BEGIN
    FOR r IN SELECT restore_sql FROM private.auth_workspace_migration_manifest
        WHERE object_kind='function' ORDER BY object_key LOOP
        EXECUTE r.restore_sql;
    END LOOP;
END $functions$;

-- These public entrypoints were created exclusively by this migration.
DROP FUNCTION public.mark_invitation_delivery(uuid,uuid,uuid,boolean,text);
DROP FUNCTION public.get_invitation_delivery_details(uuid,uuid);
DROP FUNCTION public.set_employee_removed(uuid,boolean);
DROP FUNCTION public.update_employee_access(uuid,text,text[]);
DROP FUNCTION public.list_workspace_staff(uuid);
DROP FUNCTION public.accept_workspace_invitation(uuid);
DROP FUNCTION public.cancel_workspace_invitation(uuid);
DROP FUNCTION public.reissue_workspace_invitation(uuid);
DROP FUNCTION public.create_workspace_invitation(uuid,text,text,text[],uuid);
DROP FUNCTION public.get_my_workspace_invitations(uuid);
DROP FUNCTION public.list_my_pending_invitations();
DROP FUNCTION public.create_company_workspace(text);
DROP FUNCTION public.get_my_access_context(uuid);
DROP FUNCTION public.list_my_workspaces();

DROP FUNCTION private.invitation_delivery_details(uuid,uuid);
DROP FUNCTION private.assert_workspace_manager(uuid);
DROP FUNCTION private.assert_employee_roles(text[]);
DROP FUNCTION private.has_workspace_permission(uuid,text);
DROP FUNCTION private.workspace_actor(uuid);
DROP FUNCTION private.requested_workspace();
DROP FUNCTION private.auth_identity();

DROP TABLE public.workspace_invitations;
DROP TABLE public.workspace_memberships;
ALTER TABLE public.employees DROP COLUMN legacy_auth_disabled;
ALTER TABLE public.profiles ALTER COLUMN role SET DEFAULT 'admin'::text;

DO $restore$ DECLARE r record;
BEGIN
    FOR r IN SELECT restore_sql FROM private.auth_workspace_migration_manifest
        WHERE object_kind='policy' ORDER BY object_key LOOP EXECUTE r.restore_sql; END LOOP;
    FOR r IN SELECT restore_sql FROM private.auth_workspace_migration_manifest
        WHERE object_kind IN ('function_grant','table_grant','schema_grant') ORDER BY object_kind,object_key LOOP
        EXECUTE r.restore_sql;
    END LOOP;
END $restore$;
DROP TABLE private.auth_workspace_migration_manifest;
COMMIT;
