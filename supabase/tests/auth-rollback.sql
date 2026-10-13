-- Run after migration tests and rollback. Compare equivalent metadata rather than ACL ordering.
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Local SQL tests require loopback PostgreSQL'; END IF; END $$;
SELECT test_auth.assert(to_regclass('public.workspace_memberships') IS NULL AND to_regclass('public.workspace_invitations') IS NULL,'new authentication tables removed');
SELECT test_auth.assert(NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND column_name='legacy_auth_disabled'),'legacy visibility flag reversed');
SELECT test_auth.assert((SELECT password_hash='UNCHANGED_HASH_ACTIVE' AND deleted_at IS NULL FROM public.employees WHERE username='old_active'),'rollback preserves legacy active record');
SELECT test_auth.assert((SELECT password_hash='UNCHANGED_HASH_REMOVED' AND deleted_at='2026-01-01 00:00:00+00' FROM public.employees WHERE username='old_removed'),'rollback preserves legacy removed record');
SELECT test_auth.assert((SELECT count(*)>2 AND bool_and(password_hash IS NOT NULL) FROM public.employees),'new employees survive rollback without null hashes or deletion');
SELECT test_auth.assert((SELECT technician_id=(SELECT id FROM test_auth.fixture WHERE name='tech_employee') FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000001'),'historic operational ID remains after reinvitation and rollback');

CREATE TEMP TABLE auth_after (kind text PRIMARY KEY, value jsonb NOT NULL);
INSERT INTO auth_after
SELECT 'constraints',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.constraint_name) FROM(SELECT n.nspname schema_name,c.conrelid::regclass::text table_name,c.conname constraint_name,pg_get_constraintdef(c.oid)definition FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN('public','private'))t;
INSERT INTO auth_after
SELECT 'indexes',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.indexname) FROM(SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes WHERE schemaname IN('public','private'))t;
INSERT INTO auth_after
SELECT 'triggers',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.trigger_name) FROM(SELECT n.nspname schema_name,c.relname table_name,tr.tgname trigger_name,pg_get_triggerdef(tr.oid)definition FROM pg_trigger tr JOIN pg_class c ON c.oid=tr.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT tr.tgisinternal AND n.nspname IN('public','private'))t;
INSERT INTO auth_after
SELECT 'tables',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name) FROM(SELECT n.nspname schema_name,c.relname table_name,c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner)owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private') AND c.relkind IN('r','p','v','m'))t;
INSERT INTO auth_after
SELECT 'columns', jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name) FROM(SELECT table_name,column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema='public')t;
INSERT INTO auth_after
SELECT 'policies',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.policyname) FROM(SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname IN ('public','storage'))t;
INSERT INTO auth_after
SELECT 'functions',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.function_name,t.args) FROM(SELECT n.nspname schema_name,p.proname function_name,pg_get_function_identity_arguments(p.oid)args,pg_get_functiondef(p.oid)definition,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private'))t;
INSERT INTO auth_after
SELECT 'table_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,grantee,privilege_type,is_grantable FROM information_schema.table_privileges WHERE table_schema='public')t;
INSERT INTO auth_after
SELECT 'column_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,column_name,grantee,privilege_type,is_grantable FROM information_schema.column_privileges WHERE table_schema='public')t;
INSERT INTO auth_after
SELECT 'function_acl',jsonb_agg(row_to_json(t) ORDER BY t.routine_name,t.specific_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT routine_name,specific_name,grantee,privilege_type,is_grantable FROM information_schema.routine_privileges WHERE routine_schema IN ('public','private'))t;
INSERT INTO auth_after
SELECT 'schema_acl',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT n.nspname schema_name,COALESCE(r.rolname,'PUBLIC')grantee,a.privilege_type,a.is_grantable FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl)a LEFT JOIN pg_roles r ON r.oid=a.grantee WHERE n.nspname IN('public','private'))t;
SELECT b.kind,b.value=a.value AS exact_equivalence FROM test_auth.baseline b JOIN auth_after a USING(kind) ORDER BY b.kind;
SELECT test_auth.assert((SELECT bool_and(b.value=a.value) FROM test_auth.baseline b JOIN auth_after a USING(kind)),'all original columns, function definitions, public/storage policies and table/column/function/schema privileges restored exactly');
SELECT 'PASS: schema rollback and preserved old/new operational data' AS result;
