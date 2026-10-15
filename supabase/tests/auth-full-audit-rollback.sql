CREATE TEMP TABLE full_audit_after (kind text PRIMARY KEY, value jsonb NOT NULL);
INSERT INTO full_audit_after
SELECT 'constraints',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.constraint_name) FROM(SELECT n.nspname schema_name,c.conrelid::regclass::text table_name,c.conname constraint_name,pg_get_constraintdef(c.oid)definition FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN('public','private'))t;
INSERT INTO full_audit_after
SELECT 'indexes',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.indexname) FROM(SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes WHERE schemaname IN('public','private'))t;
INSERT INTO full_audit_after
SELECT 'triggers',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name,t.trigger_name) FROM(SELECT n.nspname schema_name,c.relname table_name,tr.tgname trigger_name,pg_get_triggerdef(tr.oid)definition FROM pg_trigger tr JOIN pg_class c ON c.oid=tr.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT tr.tgisinternal AND n.nspname IN('public','private'))t;
INSERT INTO full_audit_after
SELECT 'tables',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.table_name) FROM(SELECT n.nspname schema_name,c.relname table_name,c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner)owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private') AND c.relkind IN('r','p','v','m'))t;
INSERT INTO full_audit_after
SELECT 'columns', jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name) FROM(SELECT table_name,column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema='public')t;
INSERT INTO full_audit_after
SELECT 'policies',jsonb_agg(row_to_json(t) ORDER BY t.schemaname,t.tablename,t.policyname) FROM(SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname IN ('public','storage'))t;
INSERT INTO full_audit_after
SELECT 'functions',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.function_name,t.args) FROM(SELECT n.nspname schema_name,p.proname function_name,pg_get_function_identity_arguments(p.oid)args,pg_get_functiondef(p.oid)definition,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private'))t;
INSERT INTO full_audit_after
SELECT 'table_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,grantee,privilege_type,is_grantable FROM information_schema.table_privileges WHERE table_schema='public')t;
INSERT INTO full_audit_after
SELECT 'column_acl',jsonb_agg(row_to_json(t) ORDER BY t.table_name,t.column_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT table_name,column_name,grantee,privilege_type,is_grantable FROM information_schema.column_privileges WHERE table_schema='public')t;
INSERT INTO full_audit_after
SELECT 'function_acl',jsonb_agg(row_to_json(t) ORDER BY t.routine_name,t.specific_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT routine_name,specific_name,grantee,privilege_type,is_grantable FROM information_schema.routine_privileges WHERE routine_schema IN ('public','private'))t;
INSERT INTO full_audit_after
SELECT 'schema_acl',jsonb_agg(row_to_json(t) ORDER BY t.schema_name,t.grantee,t.privilege_type,t.is_grantable) FROM(SELECT n.nspname schema_name,COALESCE(r.rolname,'PUBLIC')grantee,a.privilege_type,a.is_grantable FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl)a LEFT JOIN pg_roles r ON r.oid=a.grantee WHERE n.nspname IN('public','private'))t;
SELECT b.kind,b.value=a.value AS exact_equivalence FROM test_auth.full_audit_baseline b JOIN full_audit_after a USING(kind) ORDER BY b.kind;
SELECT test_auth.assert((SELECT bool_and(b.value=a.value) FROM test_auth.full_audit_baseline b JOIN full_audit_after a USING(kind)),'all original columns, function definitions, public/storage policies and table/column/function/schema privileges restored exactly');
SELECT 'PASS: full authorization audit rollback exact metadata equivalence' AS result;
