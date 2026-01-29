
-- Rollback Phase 3

-- 1. Restore EXECUTE (Open Access)
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- 2. Restore Old Storage Policies (ticket_photos)
DROP POLICY IF EXISTS "fp_ticket_photos_anon_select" ON storage.objects;
DROP POLICY IF EXISTS "fp_ticket_photos_anon_insert" ON storage.objects;
DROP POLICY IF EXISTS "fp_ticket_photos_anon_update" ON storage.objects;
DROP POLICY IF EXISTS "fp_ticket_photos_anon_delete" ON storage.objects;
DROP POLICY IF EXISTS "fp_ticket_photos_auth_select" ON storage.objects;
DROP POLICY IF EXISTS "fp_ticket_photos_auth_insert" ON storage.objects;
DROP POLICY IF EXISTS "fp_ticket_photos_auth_update" ON storage.objects;
DROP POLICY IF EXISTS "fp_ticket_photos_auth_delete" ON storage.objects;

-- Recreate old ones
CREATE POLICY "Admin Storage Delete" ON storage.objects FOR DELETE TO authenticated USING ((bucket_id = 'ticket_photos'::text) AND (EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND ((p.workspace_id)::text = (storage.foldername(objects.name))[1])))));
CREATE POLICY "Admin Storage Insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK ((bucket_id = 'ticket_photos'::text) AND (EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND ((p.workspace_id)::text = (storage.foldername(objects.name))[1])))));
CREATE POLICY "Admin Storage Select" ON storage.objects FOR SELECT TO authenticated USING ((bucket_id = 'ticket_photos'::text) AND (EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND ((p.workspace_id)::text = (storage.foldername(objects.name))[1])))));
CREATE POLICY "Admin Storage Update" ON storage.objects FOR UPDATE TO authenticated USING ((bucket_id = 'ticket_photos'::text) AND (EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND ((p.workspace_id)::text = (storage.foldername(objects.name))[1])))));

CREATE POLICY "Employee Storage Delete" ON storage.objects FOR DELETE TO anon, authenticated USING ((bucket_id = 'ticket_photos'::text) AND ((storage.foldername(name))[1] = ( SELECT (current_employee_from_token.workspace_id)::text AS workspace_id FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role))));
CREATE POLICY "Employee Storage Insert" ON storage.objects FOR INSERT TO anon, authenticated WITH CHECK ((bucket_id = 'ticket_photos'::text) AND ((storage.foldername(name))[1] = ( SELECT (current_employee_from_token.workspace_id)::text AS workspace_id FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role))));
CREATE POLICY "Employee Storage Select" ON storage.objects FOR SELECT TO anon, authenticated USING ((bucket_id = 'ticket_photos'::text) AND ((storage.foldername(name))[1] = ( SELECT (current_employee_from_token.workspace_id)::text AS workspace_id FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role))));
CREATE POLICY "Employee Storage Update" ON storage.objects FOR UPDATE TO anon, authenticated USING ((bucket_id = 'ticket_photos'::text) AND ((storage.foldername(name))[1] = ( SELECT (current_employee_from_token.workspace_id)::text AS workspace_id FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role))));

-- 3. Restore Old Storage Policies (workspace_logos)
DROP POLICY IF EXISTS "fp_logos_auth_insert" ON storage.objects;
DROP POLICY IF EXISTS "fp_logos_auth_update" ON storage.objects;
DROP POLICY IF EXISTS "fp_logos_auth_delete" ON storage.objects;

CREATE POLICY "Logos Secure Delete" ON storage.objects FOR DELETE TO anon, authenticated USING ((bucket_id = 'workspace_logos'::text) AND can_manage_logo(name));
CREATE POLICY "Logos Secure Update" ON storage.objects FOR UPDATE TO anon, authenticated USING ((bucket_id = 'workspace_logos'::text) AND can_manage_logo(name));
CREATE POLICY "Logos Secure Upload" ON storage.objects FOR INSERT TO anon, authenticated WITH CHECK ((bucket_id = 'workspace_logos'::text) AND can_manage_logo(name));
