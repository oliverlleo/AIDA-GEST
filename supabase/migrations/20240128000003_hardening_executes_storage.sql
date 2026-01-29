
-- Phase 3: Hardening EXECUTE and Storage

-- 1. Revoke all EXECUTE permissions
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM authenticated;

-- Grant EXECUTE to service_role (Always safe)
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- FIX: Re-grant EXECUTE on Trigger Functions to PUBLIC
-- (Triggers need to be executable by the user triggering the event)
DO $$
DECLARE
    func_record RECORD;
BEGIN
    FOR func_record IN
        SELECT n.nspname, p.proname, p.oid::regprocedure as signature
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        JOIN pg_type t ON p.prorettype = t.oid
        WHERE n.nspname = 'public' AND t.typname = 'trigger'
    LOOP
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC', func_record.signature);
    END LOOP;
END $$;

-- 2. Allowlist for Anon (Employees & Public Tracking)
GRANT EXECUTE ON FUNCTION public.employee_login(text,text,text) TO anon;
GRANT EXECUTE ON FUNCTION public.validate_employee_session(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.employee_logout(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.employee_change_password(uuid,text,text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_kpis(date,date,uuid,text,text,text,text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_operational_alerts(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_employees_for_workspace(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid,uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.current_employee_from_token() TO anon;

-- 3. Allowlist for Authenticated (Admins)
GRANT EXECUTE ON FUNCTION public.create_owner_workspace_and_profile(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_employee(uuid,text,text,text,text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_employee(uuid,text,text,text,text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_employee_password(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_logo(text) TO authenticated;

-- Shared functions for Authenticated
GRANT EXECUTE ON FUNCTION public.get_dashboard_kpis(date,date,uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_operational_alerts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_employees_for_workspace(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_employee_from_token() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid,uuid) TO authenticated;

-- 4. Storage Hardening: ticket_photos

-- Drop existing policies
DROP POLICY IF EXISTS "Admin Storage Delete" ON storage.objects;
DROP POLICY IF EXISTS "Admin Storage Insert" ON storage.objects;
DROP POLICY IF EXISTS "Admin Storage Select" ON storage.objects;
DROP POLICY IF EXISTS "Admin Storage Update" ON storage.objects;
DROP POLICY IF EXISTS "Employee Storage Delete" ON storage.objects;
DROP POLICY IF EXISTS "Employee Storage Insert" ON storage.objects;
DROP POLICY IF EXISTS "Employee Storage Select" ON storage.objects;
DROP POLICY IF EXISTS "Employee Storage Update" ON storage.objects;

-- Strict Anon Policies (Employee via Token)
CREATE POLICY "fp_ticket_photos_anon_select" ON storage.objects FOR SELECT TO anon
USING (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()));

CREATE POLICY "fp_ticket_photos_anon_insert" ON storage.objects FOR INSERT TO anon
WITH CHECK (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()));

CREATE POLICY "fp_ticket_photos_anon_update" ON storage.objects FOR UPDATE TO anon
USING (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()));

CREATE POLICY "fp_ticket_photos_anon_delete" ON storage.objects FOR DELETE TO anon
USING (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] = (SELECT workspace_id::text FROM public.current_employee_from_token()));

-- Strict Authenticated Policies (Admin via Auth)
CREATE POLICY "fp_ticket_photos_auth_select" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] IN (SELECT workspace_id::text FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "fp_ticket_photos_auth_insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] IN (SELECT workspace_id::text FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "fp_ticket_photos_auth_update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] IN (SELECT workspace_id::text FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "fp_ticket_photos_auth_delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'ticket_photos' AND (storage.foldername(name))[1] IN (SELECT workspace_id::text FROM public.profiles WHERE id = auth.uid()));

-- 5. Storage Hardening: workspace_logos

-- Drop old write policies
DROP POLICY IF EXISTS "Logos Secure Delete" ON storage.objects;
DROP POLICY IF EXISTS "Logos Secure Update" ON storage.objects;
DROP POLICY IF EXISTS "Logos Secure Upload" ON storage.objects;

-- Re-create Write Policies for Authenticated ONLY
CREATE POLICY "fp_logos_auth_insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY "fp_logos_auth_update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY "fp_logos_auth_delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));
