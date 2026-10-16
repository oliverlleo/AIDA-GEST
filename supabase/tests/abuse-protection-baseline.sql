-- Capture the deployed structure before abuse protection; local metadata only.
CREATE TABLE test_auth.abuse_baseline (kind text PRIMARY KEY,value jsonb NOT NULL);
INSERT INTO test_auth.abuse_baseline
SELECT 'constraints',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.constraint_name) FROM(SELECT n.nspname schema_name,c.conrelid::regclass::text table_name,c.conname constraint_name,pg_get_constraintdef(c.oid)definition FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN('public','private'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'indexes',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.indexname) FROM(SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes WHERE schemaname IN('public','private'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'triggers',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.trigger_name) FROM(SELECT n.nspname schema_name,c.relname table_name,tr.tgname trigger_name,pg_get_triggerdef(tr.oid)definition FROM pg_trigger tr JOIN pg_class c ON c.oid=tr.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT tr.tgisinternal AND n.nspname IN('public','private'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'tables',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name) FROM(SELECT n.nspname schema_name,c.relname table_name,c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner)owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private') AND c.relkind IN('r','p','v','m'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'columns', jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name) FROM(SELECT table_name,column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema='public')t;
INSERT INTO test_auth.abuse_baseline
SELECT 'policies',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.policyname) FROM(SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname IN ('public','storage'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'functions',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.function_name,t.args) FROM(SELECT n.nspname schema_name,p.proname function_name,pg_get_function_identity_arguments(p.oid)args,pg_get_functiondef(p.oid)definition,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'table_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,grantee,privilege_type,is_grantable FROM information_schema.table_privileges WHERE table_schema='public')t;
INSERT INTO test_auth.abuse_baseline
SELECT 'column_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,column_name,grantee,privilege_type,is_grantable FROM information_schema.column_privileges WHERE table_schema='public')t;
INSERT INTO test_auth.abuse_baseline
SELECT 'function_acl',jsonb_agg(row_to_json(t) ORDER BY t.routine_name,t.specific_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT routine_name,specific_name,grantee,privilege_type,is_grantable FROM information_schema.routine_privileges WHERE routine_schema IN ('public','private'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'schema_acl',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT n.nspname schema_name,COALESCE(r.rolname,'PUBLIC')grantee,a.privilege_type,a.is_grantable FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl)a LEFT JOIN pg_roles r ON r.oid=a.grantee WHERE n.nspname IN('public','private'))t;
INSERT INTO test_auth.abuse_baseline
SELECT 'graphql_schema_acl',coalesce(jsonb_agg(jsonb_build_object('schema',nspname,'acl',nspacl::text) ORDER BY nspname),'[]'::jsonb)
FROM pg_namespace WHERE nspname IN ('graphql','graphql_public');
INSERT INTO test_auth.abuse_baseline
SELECT 'request_hook',coalesce(jsonb_agg(c ORDER BY c),'[]'::jsonb)
FROM pg_db_role_setting s CROSS JOIN LATERAL unnest(s.setconfig)c
WHERE s.setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database())
 AND s.setrole=(SELECT oid FROM pg_roles WHERE rolname='authenticator') AND c LIKE 'pgrst.db_pre_request=%';
INSERT INTO test_auth.abuse_baseline
SELECT 'storage_bucket_configuration',coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'public',public,
 'file_size_limit',file_size_limit,'allowed_mime_types',allowed_mime_types) ORDER BY id),'[]'::jsonb)
FROM storage.buckets WHERE id IN('ticket_photos','workspace_logos','inventory_images');
