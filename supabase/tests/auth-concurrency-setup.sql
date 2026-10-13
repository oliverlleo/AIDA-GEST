-- Fresh invitation for two real concurrent PostgreSQL connections with the same verified Auth session.
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Local SQL tests require loopback PostgreSQL'; END IF; END $$;
SET ROLE authenticated;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO test_auth.fixture SELECT 'concurrent_invite',public.create_workspace_invitation('20000000-0000-4000-8000-000000000002','Concurrent acceptance fixture','fixture6@example.invalid',ARRAY['tecnico']);
INSERT INTO test_auth.fixture SELECT 'concurrent_employee',employee_id FROM public.get_my_workspace_invitations('20000000-0000-4000-8000-000000000002') WHERE invitation_id=(SELECT id FROM test_auth.fixture WHERE name='concurrent_invite');
RESET ROLE;
