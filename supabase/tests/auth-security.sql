-- Local synthetic integration tests. Intentionally retain fixtures to exercise the rollback afterward.
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Local SQL tests require loopback PostgreSQL'; END IF; END $$;
SELECT test_auth.assert((SELECT bool_and(legacy_auth_disabled) FROM public.employees),'legacy employees retired reversibly');
SELECT test_auth.assert((SELECT password_hash='UNCHANGED_HASH_ACTIVE' AND deleted_at IS NULL FROM public.employees WHERE username='old_active'),'old credentials and deletion unchanged');
SELECT test_auth.assert((SELECT count(*)=2 FROM public.workspace_memberships),'only trusted owners backfilled');
SELECT test_auth.assert(NOT has_function_privilege('anon','public.employee_login(text,text,text)','EXECUTE'),'anonymous legacy login revoked');
SELECT test_auth.assert(NOT has_function_privilege('authenticated','public.create_employee(uuid,text,text,text,text[])','EXECUTE'),'legacy management revoked');
SELECT test_auth.assert(NOT has_column_privilege('authenticated','public.employees','password_hash','SELECT'),'employee password hash protected');
SELECT test_auth.assert(NOT has_table_privilege('anon','public.tickets','SELECT'),'business anonymous access revoked');
SELECT test_auth.assert(has_function_privilege('anon','public.get_client_ticket_details_public(uuid,uuid)','EXECUTE'),'public token tracker retained');

SET ROLE authenticated;
SELECT test_auth.login(6);
SELECT test_auth.assert((SELECT count(*)=0 FROM public.list_my_workspaces()),'no automatic company on signup');
SELECT test_auth.expect_error($q$INSERT INTO public.profiles(id,workspace_id,role) VALUES('10000000-0000-4000-8000-000000000006','20000000-0000-4000-8000-000000000002','admin')$q$,'42501');
SELECT test_auth.login(7);
SELECT test_auth.expect_error('SELECT public.list_my_workspaces()','42501');
SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000001');
SELECT test_auth.assert((public.get_my_access_context('20000000-0000-4000-8000-000000000001')->'roles')='["admin"]','owner A retained');
SELECT test_auth.expect_error('SELECT public.get_my_access_context(''20000000-0000-4000-8000-000000000002'')','42501');
SELECT test_auth.expect_error('SELECT public.create_company_workspace(''Duplicate company'')');

SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO test_auth.fixture SELECT 'owner_employee_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Owner A at B','fixture1@example.invalid',ARRAY['tecnico']);
INSERT INTO test_auth.fixture SELECT 'tech_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Technician','fixture3@example.invalid',ARRAY['tecnico']);
INSERT INTO test_auth.fixture SELECT 'attendant_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Attendant','fixture4@example.invalid',ARRAY['atendente']);
INSERT INTO test_auth.fixture SELECT 'tester_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Tester','fixture5@example.invalid',ARRAY['tester']);
INSERT INTO test_auth.fixture SELECT 'admin_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Administrator','fixture8@example.invalid',ARRAY['admin']);
INSERT INTO test_auth.fixture SELECT 'unconfirmed_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Unconfirmed','fixture7@example.invalid',ARRAY['tecnico']);
INSERT INTO test_auth.fixture SELECT 'expiry_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Expiring','fixture6@example.invalid',ARRAY['tecnico']);
SELECT test_auth.expect_error('SELECT public.create_workspace_invitation(''20000000-0000-4000-8000-000000000002'',''Duplicate'',''fixture3@example.invalid'',ARRAY[''admin''])','23505');
SELECT test_auth.expect_error('SELECT public.create_workspace_invitation(''20000000-0000-4000-8000-000000000002'',''Bad role'',''unknown@example.invalid'',ARRAY[''superuser''])','22023');
SELECT test_auth.expect_error('SELECT public.create_workspace_invitation(''20000000-0000-4000-8000-000000000001'',''Foreign'',''foreign@example.invalid'',ARRAY[''admin''])','42501');
INSERT INTO test_auth.fixture SELECT 'tech_employee',employee_id FROM public.get_my_workspace_invitations('20000000-0000-4000-8000-000000000002') WHERE invitation_id=(SELECT id FROM test_auth.fixture WHERE name='tech_invite');
INSERT INTO test_auth.fixture SELECT 'owner_employee',employee_id FROM public.get_my_workspace_invitations('20000000-0000-4000-8000-000000000002') WHERE invitation_id=(SELECT id FROM test_auth.fixture WHERE name='owner_employee_invite');
INSERT INTO test_auth.fixture SELECT 'tester_employee',employee_id FROM public.get_my_workspace_invitations('20000000-0000-4000-8000-000000000002') WHERE invitation_id=(SELECT id FROM test_auth.fixture WHERE name='tester_invite');
INSERT INTO test_auth.fixture SELECT 'admin_employee',employee_id FROM public.get_my_workspace_invitations('20000000-0000-4000-8000-000000000002') WHERE invitation_id=(SELECT id FROM test_auth.fixture WHERE name='admin_invite');

SELECT test_auth.login(6);
SELECT test_auth.expect_error('SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name=''tech_invite''))','42501');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.list_my_pending_invitations()),'pending discovery uses verified database email, ignores JWT forged email');
SELECT test_auth.login(7);
SELECT test_auth.expect_error('SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name=''unconfirmed_invite''))','42501');
SELECT test_auth.login(1);
SELECT test_auth.assert(public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='owner_employee_invite'))='20000000-0000-4000-8000-000000000002','owner joins second company');
SELECT test_auth.assert(public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='owner_employee_invite'))='20000000-0000-4000-8000-000000000002','acceptance idempotent');
SELECT test_auth.assert((SELECT count(*)=2 FROM public.list_my_workspaces()),'owner company preserved after accepting other');
SELECT test_auth.login(3);
SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='tech_invite'));
SELECT test_auth.login(4);
SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='attendant_invite'));
SELECT test_auth.login(5);
SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='tester_invite'));
SELECT test_auth.login(8);
SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='admin_invite'));

RESET ROLE;
UPDATE public.workspace_invitations SET expires_at=now()-interval '1 second' WHERE id=(SELECT id FROM test_auth.fixture WHERE name='expiry_invite');
SET ROLE authenticated;
SELECT test_auth.login(6);
SELECT test_auth.expect_error('SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name=''expiry_invite''))','22023');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO test_auth.fixture SELECT 'reissued_invite',public.reissue_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='expiry_invite'));
SELECT test_auth.assert((SELECT id FROM test_auth.fixture WHERE name='reissued_invite')<>(SELECT id FROM test_auth.fixture WHERE name='expiry_invite'),'reissue invalidates old link');
SELECT public.cancel_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='reissued_invite'));
SELECT test_auth.login(6);
SELECT test_auth.expect_error('SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name=''reissued_invite''))','22023');

SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.assert((SELECT actor_kind='employee' AND actor_user_id IS NULL AND actor_employee_id=(SELECT id FROM test_auth.fixture WHERE name='owner_employee') AND NOT is_admin FROM public.get_current_actor_context()),'owner A restricted as technician B with XOR identity');
SELECT test_auth.assert(NOT public.can_manage_workspace('20000000-0000-4000-8000-000000000002'),'owner A cannot manage B');
SELECT test_auth.assert(NOT public.can_manage_workspace('20000000-0000-4000-8000-000000000001'),'selected B blocks operations directed at A');
SELECT test_auth.expect_error('SELECT public.list_workspace_staff(''20000000-0000-4000-8000-000000000002'')','42501');
SELECT test_auth.expect_error('UPDATE public.employees SET roles=ARRAY[''admin''] WHERE id=(SELECT id FROM test_auth.fixture WHERE name=''owner_employee'')','42501');
SELECT test_auth.expect_error('SELECT password_hash FROM public.employees','42501');
SELECT test_auth.expect_error('INSERT INTO public.device_models(workspace_id,name) VALUES(''20000000-0000-4000-8000-000000000002'',''Unauthorised catalog write'')','42501');

SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,created_by,created_by_name)
VALUES('50000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','Synthetic client','REVIEW_B_OWN','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='tech_employee'),'Analise Tecnica','10000000-0000-4000-8000-000000000006','Forged actor'),
      ('50000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','Synthetic client','REVIEW_B_OTHER','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='owner_employee'),'Analise Tecnica',NULL,NULL),
      ('50000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002','Synthetic client','REVIEW_B_TEST','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='owner_employee'),'Teste Final',NULL,NULL);
SELECT test_auth.assert((SELECT created_by='10000000-0000-4000-8000-000000000002' AND created_by_name='Fixture 2' FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000001'),'server stamps actor identity');
INSERT INTO test_auth.fixture SELECT 'public_token',public_token FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000001';
SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000001');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status)
VALUES('50000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000001','Synthetic client A','REVIEW_A','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days','30000000-0000-4000-8000-000000000001','Analise Tecnica');
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.tickets),'technician sees assigned ticket only, no other company');
SELECT test_auth.assert((SELECT count(*)=0 FROM public.tickets WHERE workspace_id='20000000-0000-4000-8000-000000000001'),'workspace isolation');
SELECT public.get_schedule_availability((SELECT id FROM test_auth.fixture WHERE name='tech_employee'),'analysis',current_date,1);
SELECT public.start_ticket_analysis('50000000-0000-4000-8000-000000000001');
INSERT INTO public.internal_notes(workspace_id,ticket_id,content,author_id,author_name)
VALUES('20000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000001','Synthetic note','10000000-0000-4000-8000-000000000006','Forged author');
SELECT test_auth.assert((SELECT author_id=(SELECT id FROM test_auth.fixture WHERE name='tech_employee') AND author_name='Technician' FROM public.internal_notes WHERE content='Synthetic note'),'employee note attribution preserved');
INSERT INTO storage.objects(bucket_id,name) VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000001/photo.jpg');
UPDATE storage.objects SET metadata='{}'::jsonb WHERE bucket_id='ticket_photos';
SELECT test_auth.assert((SELECT count(*)=1 FROM storage.objects WHERE bucket_id='ticket_photos'),'authenticated technician photo upload/read/upsert preserved');
SELECT test_auth.expect_error('INSERT INTO storage.objects(bucket_id,name) VALUES(''ticket_photos'',''20000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000004/photo.jpg'')','42501');
SELECT test_auth.expect_error('INSERT INTO storage.objects(bucket_id,name) VALUES(''workspace_logos'',''20000000-0000-4000-8000-000000000002/logo.png'')','42501');

SELECT test_auth.login(5,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.tickets),'tester sees test ticket only');
SELECT test_auth.expect_error('INSERT INTO storage.objects(bucket_id,name) VALUES(''ticket_photos'',''20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000003/test.jpg'')','42501');
SELECT test_auth.login(4,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.assert((SELECT count(*)=3 FROM public.tickets),'attendant sees own company tickets');
INSERT INTO public.device_models(workspace_id,name) VALUES('20000000-0000-4000-8000-000000000002','Allowed catalog write');
SELECT test_auth.expect_error('SELECT public.list_workspace_staff(''20000000-0000-4000-8000-000000000002'')','42501');

SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='tech_employee'),'Technician',ARRAY['tecnico','atendente']);
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.assert((SELECT is_attendant FROM public.get_current_actor_context()),'role change effective for existing JWT');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='tech_employee'),'Technician',ARRAY['tecnico']);
SELECT public.set_employee_account_blocked((SELECT id FROM test_auth.fixture WHERE name='owner_employee'),true,'Synthetic block');
SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.expect_error('SELECT public.get_current_actor_context()','42501');
SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000001');
SELECT test_auth.assert((SELECT is_admin FROM public.get_current_actor_context()),'block B does not block owner A');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.set_employee_account_blocked((SELECT id FROM test_auth.fixture WHERE name='owner_employee'),false,NULL);
SELECT public.revoke_employee_sessions((SELECT id FROM test_auth.fixture WHERE name='tech_employee'));
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.expect_error('SELECT public.get_current_actor_context()','42501');
SELECT test_auth.assert((SELECT requires_reauthentication FROM public.list_my_workspaces()),'revoked session flags reauthentication');
SELECT set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || jsonb_build_object('iat',extract(epoch FROM clock_timestamp())::integer))::text,false);
SELECT test_auth.expect_error('SELECT public.get_current_actor_context()','42501');
RESET ROLE;
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('11000000-0000-4000-8000-000000000103','10000000-0000-4000-8000-000000000003',clock_timestamp());
SET ROLE authenticated;
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000103');
SELECT test_auth.assert((SELECT is_technician FROM public.get_current_actor_context()),'new sign-in session restores local access');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.set_employee_removed((SELECT id FROM test_auth.fixture WHERE name='tech_employee'),true);
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000103');
SELECT test_auth.expect_error('SELECT public.get_current_actor_context()','42501');

RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"anon"}',false),set_config('request.headers','{}',false);
GRANT SELECT ON test_auth.fixture TO anon;
SET ROLE anon;
SELECT test_auth.assert((SELECT count(*)=1 FROM public.get_client_ticket_details_public('50000000-0000-4000-8000-000000000001',(SELECT id FROM test_auth.fixture WHERE name='public_token'))),'public tracker token retained without login');
SELECT test_auth.assert((SELECT count(*)=0 FROM public.get_client_ticket_details_public('50000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000000')),'incorrect public token denied');
SELECT test_auth.expect_error('SELECT public.list_my_workspaces()','42501');
SELECT test_auth.expect_error('SELECT * FROM public.tickets','42501');
RESET ROLE;
SELECT 'PASS: identity, invitations, tenant and role isolation, Storage, live revocation, public tracker' AS result;
