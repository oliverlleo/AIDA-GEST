DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Local SQL tests require loopback PostgreSQL'; END IF; END $$;
SET application_name='aida_auth_accept_first';
BEGIN;
SET ROLE authenticated;
SELECT test_auth.login(6);
SELECT public.accept_workspace_invitation((SELECT id FROM test_auth.fixture WHERE name='concurrent_invite'));
-- Runner starts the second connection only after observing this flushed marker.
SELECT 'LOCK_HELD';
SELECT pg_sleep(1);
COMMIT;
