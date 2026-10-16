-- Structural local-only snapshot for exact rollback comparison; contains no rows.
CREATE TABLE test_auth.ticket_concurrency_baseline(kind text PRIMARY KEY,value jsonb NOT NULL);
INSERT INTO test_auth.ticket_concurrency_baseline
SELECT 'functions',coalesce(jsonb_agg(to_jsonb(x) ORDER BY schema_name,function_name,args),'[]'::jsonb)
FROM(SELECT n.nspname schema_name,p.proname function_name,pg_get_function_identity_arguments(p.oid)args,
 md5(pg_get_functiondef(p.oid)) definition_md5,pg_get_userbyid(p.proowner)owner,p.proacl::text acl,p.proconfig
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private') AND p.prokind IN('f','p'))x;
INSERT INTO test_auth.ticket_concurrency_baseline
SELECT 'ticket_columns',coalesce(jsonb_agg(to_jsonb(x) ORDER BY ordinal_position),'[]'::jsonb)
FROM(SELECT column_name,ordinal_position,data_type,is_nullable,column_default,udt_schema,udt_name
 FROM information_schema.columns WHERE table_schema='public' AND table_name='tickets')x;
INSERT INTO test_auth.ticket_concurrency_baseline
SELECT 'constraints',coalesce(jsonb_agg(to_jsonb(x) ORDER BY schema_name,table_name,name),'[]'::jsonb)
FROM(SELECT n.nspname schema_name,c.conrelid::regclass::text table_name,c.conname name,pg_get_constraintdef(c.oid)definition
 FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN('public','private'))x;
INSERT INTO test_auth.ticket_concurrency_baseline
SELECT 'indexes',coalesce(jsonb_agg(to_jsonb(x) ORDER BY schemaname,tablename,indexname),'[]'::jsonb)
FROM(SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes WHERE schemaname IN('public','private'))x;
INSERT INTO test_auth.ticket_concurrency_baseline
SELECT 'triggers',coalesce(jsonb_agg(to_jsonb(x) ORDER BY schema_name,table_name,trigger_name),'[]'::jsonb)
FROM(SELECT n.nspname schema_name,c.relname table_name,t.tgname trigger_name,pg_get_triggerdef(t.oid)definition
 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND n.nspname IN('public','private'))x;
INSERT INTO test_auth.ticket_concurrency_baseline
SELECT 'policies',coalesce(jsonb_agg(to_jsonb(x) ORDER BY schemaname,tablename,policyname),'[]'::jsonb)
FROM(SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname IN('public','private','storage'))x;
INSERT INTO test_auth.ticket_concurrency_baseline
SELECT 'ticket_acl',coalesce(jsonb_agg(to_jsonb(x) ORDER BY grantee,privilege_type,is_grantable),'[]'::jsonb)
FROM(SELECT grantee,privilege_type,is_grantable FROM information_schema.table_privileges WHERE table_schema='public' AND table_name='tickets')x;
