-- Local synthetic harness only: NEVER deploy these Realtime stubs.
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR inet_server_port()<>54329
    OR current_database() NOT LIKE 'aida_auth_review_%' THEN
  RAISE EXCEPTION 'Named loopback synthetic database required';
 END IF;
 IF to_regclass('realtime.messages') IS NOT NULL OR to_regprocedure('realtime.send(jsonb,text,text,boolean)') IS NOT NULL THEN
  RAISE EXCEPTION 'This isolated harness expects absent Realtime; never replace managed objects';
 END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS realtime AUTHORIZATION postgres;
CREATE TABLE realtime.messages (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),topic text NOT NULL,extension text NOT NULL,
 payload jsonb NOT NULL,event text NOT NULL,"private" boolean NOT NULL DEFAULT true
);
ALTER TABLE realtime.messages OWNER TO postgres;
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA realtime TO authenticated,anon;
GRANT SELECT ON realtime.messages TO authenticated,anon;
GRANT INSERT ON realtime.messages TO authenticated;
CREATE FUNCTION realtime.topic() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('realtime.topic',true),'');
$$;
CREATE FUNCTION realtime.send(payload jsonb,event text,topic text,"private" boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql AS $$ BEGIN
 IF current_setting('aida.test_sync_send_failure',true)='true' THEN RAISE EXCEPTION 'Synthetic broker failure'; END IF;
 INSERT INTO realtime.messages(payload,event,topic,"private",extension) VALUES(payload,event,topic,"private",'broadcast');
END $$;
ALTER FUNCTION realtime.send(jsonb,text,text,boolean) OWNER TO postgres;
CREATE FUNCTION test_auth.workspace_sync_snapshot() RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
 'functions',(SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'args',pg_get_function_identity_arguments(p.oid),'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',pg_get_userbyid(p.proowner)) ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),'[]'::jsonb) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private')),
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid)) ORDER BY n.nspname,c.relname,t.tgname),'[]'::jsonb) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN('public','private','realtime')),
 'policies',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.schemaname,p.tablename,p.policyname),'[]'::jsonb) FROM pg_policies p WHERE schemaname IN('public','private','storage','realtime')),
 'relations',(SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text,'owner',pg_get_userbyid(c.relowner)) ORDER BY n.nspname,c.relname),'[]'::jsonb) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','storage','realtime') AND c.relkind IN('r','p','v','m')),
 'columns',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.table_schema,c.table_name,c.ordinal_position),'[]'::jsonb) FROM information_schema.columns c WHERE table_schema IN('public','private','storage','realtime')),
 'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.conrelid::regclass::text,'name',c.conname,'definition',pg_get_constraintdef(c.oid)) ORDER BY n.nspname,c.conrelid::regclass::text,c.conname),'[]'::jsonb) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN('public','private','storage','realtime')),
 'indexes',(SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.schemaname,i.tablename,i.indexname),'[]'::jsonb) FROM pg_indexes i WHERE schemaname IN('public','private','storage','realtime')),
 'publications',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.pubname,p.schemaname,p.tablename),'[]'::jsonb) FROM pg_publication_tables p),
 'schema_acl',(SELECT coalesce(jsonb_agg(jsonb_build_object('schema',nspname,'acl',nspacl::text) ORDER BY nspname),'[]'::jsonb) FROM pg_namespace WHERE nspname IN('public','private','storage','realtime'))
 );
$$;
CREATE TABLE test_auth.workspace_sync_baseline(snapshot jsonb NOT NULL);
INSERT INTO test_auth.workspace_sync_baseline VALUES(test_auth.workspace_sync_snapshot());
SELECT 'PASS: isolated Realtime harness and nine structural baseline groups' AS result;
