-- Synthetic local-only fixtures. Run after LOCAL_TEST_BOOTSTRAP.sql + baseline.sql, before migration.
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Local SQL tests require loopback PostgreSQL'; END IF; END $$;
-- Managed definers are owned by postgres; the portable local runtime installs extensions as its test administrator.
GRANT USAGE ON SCHEMA extensions TO postgres;
CREATE SCHEMA test_auth;
CREATE TABLE test_auth.fixture (name text PRIMARY KEY, id uuid NOT NULL);
GRANT USAGE ON SCHEMA test_auth TO authenticated, anon, service_role;
GRANT ALL ON test_auth.fixture TO authenticated, service_role;
CREATE FUNCTION test_auth.assert(p_ok boolean, p_message text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Assertion failed: %',p_message; END IF; END $$;
CREATE FUNCTION test_auth.expect_error(p_sql text, p_state text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    BEGIN EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
        IF p_state IS NOT NULL AND v_state <> p_state THEN RAISE EXCEPTION 'Expected SQLSTATE %, got % for %',p_state,v_state,p_sql; END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'Expected rejection: %',p_sql;
END $$;
CREATE FUNCTION test_auth.login(p_number integer,p_workspace uuid DEFAULT NULL,p_session uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_uid uuid := ('10000000-0000-4000-8000-' || lpad(p_number::text,12,'0'))::uuid;
BEGIN
    PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',v_uid,'session_id',COALESCE(p_session,('11000000-0000-4000-8000-' || lpad(p_number::text,12,'0'))::uuid),'email','forged@example.invalid','user_metadata',jsonb_build_object('role','admin'))::text,false);
    PERFORM set_config('request.headers',jsonb_build_object('x-workspace-id',p_workspace,'x-employee-token','40000000-0000-4000-8000-000000000001')::text,false);
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at,raw_user_meta_data,created_at,updated_at)
SELECT ('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,'fixture'||n||'@example.invalid',CASE WHEN n <> 7 THEN now() END,jsonb_build_object('full_name','Fixture '||n,'role','admin'),now(),now() FROM generate_series(1,8) n;
INSERT INTO auth.sessions(id,user_id,created_at)
SELECT ('11000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,now()-interval '1 hour' FROM generate_series(1,8)n;
INSERT INTO public.workspaces(id,name,company_code,owner_id)
VALUES('20000000-0000-4000-8000-000000000001','Fixture A','TEST_COMPANY_A','10000000-0000-4000-8000-000000000001'),
      ('20000000-0000-4000-8000-000000000002','Fixture B','TEST_COMPANY_B','10000000-0000-4000-8000-000000000002');
INSERT INTO public.profiles(id,workspace_id,role) VALUES('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','admin'),('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','admin');
INSERT INTO public.employees(id,workspace_id,name,username,password_hash,roles,deleted_at)
VALUES('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Old active','old_active','UNCHANGED_HASH_ACTIVE',ARRAY['tecnico'],NULL),
      ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','Old removed','old_removed','UNCHANGED_HASH_REMOVED',ARRAY['atendente'],'2026-01-01 00:00:00+00');
-- Match the exported production bucket configuration before abuse protection.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('ticket_photos','ticket_photos',false,NULL,NULL),
      ('inventory_images','inventory_images',false,5242880,ARRAY['image/jpeg','image/png','image/webp']),
      ('workspace_logos','workspace_logos',true,NULL,NULL);

CREATE TABLE test_auth.baseline (kind text PRIMARY KEY, value jsonb NOT NULL);
INSERT INTO test_auth.baseline
SELECT 'constraints',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.constraint_name) FROM(SELECT n.nspname schema_name,c.conrelid::regclass::text table_name,c.conname constraint_name,pg_get_constraintdef(c.oid)definition FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN('public','private'))t;
INSERT INTO test_auth.baseline
SELECT 'indexes',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.indexname) FROM(SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes WHERE schemaname IN('public','private'))t;
INSERT INTO test_auth.baseline
SELECT 'triggers',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.trigger_name) FROM(SELECT n.nspname schema_name,c.relname table_name,tr.tgname trigger_name,pg_get_triggerdef(tr.oid)definition FROM pg_trigger tr JOIN pg_class c ON c.oid=tr.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT tr.tgisinternal AND n.nspname IN('public','private'))t;
INSERT INTO test_auth.baseline
SELECT 'tables',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name) FROM(SELECT n.nspname schema_name,c.relname table_name,c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner)owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private') AND c.relkind IN('r','p','v','m'))t;
INSERT INTO test_auth.baseline
SELECT 'columns', jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name) FROM(SELECT table_name,column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema='public')t;
INSERT INTO test_auth.baseline
SELECT 'policies',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.policyname) FROM(SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname IN ('public','storage'))t;
INSERT INTO test_auth.baseline
SELECT 'functions',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.function_name,t.args) FROM(SELECT n.nspname schema_name,p.proname function_name,pg_get_function_identity_arguments(p.oid)args,pg_get_functiondef(p.oid)definition,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private'))t;
INSERT INTO test_auth.baseline
SELECT 'table_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,grantee,privilege_type,is_grantable FROM information_schema.table_privileges WHERE table_schema='public')t;
INSERT INTO test_auth.baseline
SELECT 'column_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,column_name,grantee,privilege_type,is_grantable FROM information_schema.column_privileges WHERE table_schema='public')t;
INSERT INTO test_auth.baseline
SELECT 'function_acl',jsonb_agg(row_to_json(t) ORDER BY t.routine_name,t.specific_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT routine_name,specific_name,grantee,privilege_type,is_grantable FROM information_schema.routine_privileges WHERE routine_schema IN ('public','private'))t;
INSERT INTO test_auth.baseline
SELECT 'schema_acl',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT n.nspname schema_name,COALESCE(r.rolname,'PUBLIC')grantee,a.privilege_type,a.is_grantable FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl)a LEFT JOIN pg_roles r ON r.oid=a.grantee WHERE n.nspname IN('public','private'))t;
