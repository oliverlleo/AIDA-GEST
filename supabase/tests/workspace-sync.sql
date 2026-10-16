\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR inet_server_port()<>54329
    OR current_database() NOT LIKE 'aida_auth_review_%' THEN RAISE EXCEPTION 'Named loopback synthetic database required'; END IF;
END $$;
-- Earlier committed synthetic race tests may have emitted broker hints. Isolate
-- this transaction's broker fixtures; ROLLBACK restores the surrounding harness.
DELETE FROM realtime.messages;
SELECT test_auth.assert((SELECT count(*)=36 FROM pg_trigger WHERE tgname='aida_workspace_sync' AND NOT tgisinternal),'36 business table invalidation triggers');
SELECT test_auth.assert((SELECT count(*)=3 AND bool_and(p.prosecdef AND pg_get_userbyid(p.proowner)='postgres' AND p.proconfig=ARRAY['search_path=""']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN('can_receive_workspace_sync','publish_workspace_sync','emit_workspace_sync')),'three private definers have pinned empty search path and production owner');
SELECT test_auth.assert(NOT has_function_privilege('anon','private.can_receive_workspace_sync(text)','EXECUTE') AND has_function_privilege('authenticated','private.can_receive_workspace_sync(text)','EXECUTE') AND NOT has_function_privilege('authenticated','private.publish_workspace_sync(uuid,text)','EXECUTE') AND NOT has_function_privilege('authenticated','private.emit_workspace_sync()','EXECUTE'),'only authenticated receive helper is callable by clients');
SELECT test_auth.assert((SELECT count(*)=1 AND bool_and(cmd='SELECT' AND roles=ARRAY['authenticated']::name[]) FROM pg_policies WHERE schemaname='realtime' AND policyname='aida_workspace_sync_receive'),'receive-only authenticated Realtime policy');
-- Controlled broker messages demonstrate both current topic and extension/private isolation.
INSERT INTO realtime.messages(topic,extension,payload,event,"private") VALUES
 ('workspace:20000000-0000-4000-8000-000000000001','broadcast','{"scope":"tickets"}','invalidate',true),
 ('workspace:20000000-0000-4000-8000-000000000002','broadcast','{"scope":"tickets"}','invalidate',true),
 ('workspace:20000000-0000-4000-8000-000000000002','presence','{}','test',true),
 ('workspace:20000000-0000-4000-8000-000000000002','broadcast','{}','test',false);
INSERT INTO auth.sessions(id,user_id,created_at)
SELECT ('93fd8419-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,clock_timestamp() FROM generate_series(1,8)n;
SELECT test_auth.login(2,NULL,'93fd8419-0000-4000-8000-000000000002');
SELECT set_config('request.headers','{}',true);
SELECT set_config('realtime.topic','workspace:20000000-0000-4000-8000-000000000002',true);
SET LOCAL ROLE authenticated;
SELECT test_auth.assert(private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002'),'owner can join without browser workspace header');
SELECT test_auth.assert(NOT private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000001'),'owner cannot join another company');
SELECT test_auth.assert(NOT private.can_receive_workspace_sync(NULL) AND NOT private.can_receive_workspace_sync('workspace:bad') AND NOT private.can_receive_workspace_sync('tickets_channel') AND NOT private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002:extra'),'malformed or unscoped topics denied');
SELECT test_auth.assert((SELECT count(*)=1 FROM realtime.messages),'only private broadcasts of authorized current topic are visible');
SELECT test_auth.expect_error($q$INSERT INTO realtime.messages(topic,extension,payload,event,"private") VALUES('workspace:20000000-0000-4000-8000-000000000002','broadcast','{}','invalidate',true)$q$,'42501');
SELECT test_auth.expect_error($q$SELECT private.publish_workspace_sync('20000000-0000-4000-8000-000000000002','tickets')$q$,'42501');
RESET ROLE;
SELECT test_auth.login(7,NULL,'93fd8419-0000-4000-8000-000000000007');
SET LOCAL ROLE authenticated;
SELECT test_auth.assert(NOT private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002'),'unconfirmed account cannot join');
RESET ROLE;
SELECT test_auth.login(3,NULL,'93fd8419-0000-4000-8000-000000000003');
SET LOCAL ROLE authenticated;
SELECT test_auth.assert(private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002'),'active employee can join without headers');
RESET ROLE;
INSERT INTO public.employee_auth_state(employee_id,manual_blocked)
SELECT employee_id,true FROM public.workspace_memberships WHERE workspace_id='20000000-0000-4000-8000-000000000002' AND user_id='10000000-0000-4000-8000-000000000003'
ON CONFLICT(employee_id) DO UPDATE SET manual_blocked=true;
SET LOCAL ROLE authenticated;
SELECT test_auth.assert(NOT private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002'),'blocked employee rejected on policy re-evaluation');
RESET ROLE;
UPDATE public.employee_auth_state SET manual_blocked=false WHERE employee_id=(SELECT employee_id FROM public.workspace_memberships WHERE workspace_id='20000000-0000-4000-8000-000000000002' AND user_id='10000000-0000-4000-8000-000000000003');
UPDATE public.workspace_memberships SET status='revoked' WHERE workspace_id='20000000-0000-4000-8000-000000000002' AND user_id='10000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SELECT test_auth.assert(NOT private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002'),'removed membership rejected');
RESET ROLE;
UPDATE public.workspace_memberships SET status='active',session_valid_after=clock_timestamp()+interval '1 second' WHERE workspace_id='20000000-0000-4000-8000-000000000002' AND user_id='10000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SELECT test_auth.assert(NOT private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002'),'previously issued session rejected after company revocation');
RESET ROLE;
SELECT test_auth.login(1,NULL,'93fd8419-0000-4000-8000-000000000001');
SET LOCAL ROLE authenticated;
SELECT test_auth.assert(private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000001') AND private.can_receive_workspace_sync('workspace:20000000-0000-4000-8000-000000000002'),'owner A employed in B can join both legitimate channels');
RESET ROLE;
SELECT set_config('request.jwt.claims','{}',true);
SET LOCAL ROLE anon;
SELECT test_auth.assert((SELECT count(*)=0 FROM realtime.messages),'anonymous client receives no private hints');
RESET ROLE;

-- The harness records server emissions, never business records, to test payload minimization.
DELETE FROM realtime.messages;
SELECT set_config('aida.workspace_sync_seen','{}',true);
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','93fd8419-0000-4000-8000-000000000002');
UPDATE public.tickets SET tech_notes='SYNTHETIC PRIVATE TEXT NEVER IN BROADCAST' WHERE workspace_id='20000000-0000-4000-8000-000000000002';
UPDATE public.tickets SET tech_notes='SYNTHETIC SECOND WRITE' WHERE workspace_id='20000000-0000-4000-8000-000000000002';
SELECT test_auth.assert((SELECT count(*)=3 AND count(DISTINCT payload->>'scope')=3 FROM realtime.messages),'many ticket rows and repeated writes coalesce to three scoped hints per transaction');
SELECT test_auth.assert((SELECT bool_and(event='invalidate' AND "private" AND topic='workspace:20000000-0000-4000-8000-000000000002' AND payload IN ('{"scope":"tickets"}'::jsonb,'{"scope":"agenda"}'::jsonb,'{"scope":"notifications"}'::jsonb)) FROM realtime.messages),'broadcast payloads contain only a scope and use private workspace channels');
DELETE FROM realtime.messages;
SELECT set_config('aida.workspace_sync_seen','{}',true);
UPDATE public.inventory_items SET internal_notes='SYNTHETIC INVENTORY SECRET' WHERE workspace_id='20000000-0000-4000-8000-000000000002';
SELECT test_auth.assert((SELECT count(*)=1 AND bool_and(payload='{"scope":"inventory"}'::jsonb) FROM realtime.messages),'inventory changes produce only inventory invalidation');
DELETE FROM realtime.messages;
SELECT set_config('aida.workspace_sync_seen','{}',true);
INSERT INTO public.internal_notes(workspace_id,author_id,author_name,content)
VALUES('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Synthetic owner','SYNTHETIC NOTE SECRET');
-- Resolve workspace for tables without workspace_id via their existing business FK.
INSERT INTO public.notifications(ticket_id,recipient_role,type,message)
SELECT id,'admin','sync_test','SYNTHETIC NOTIFICATION SECRET' FROM public.tickets WHERE workspace_id='20000000-0000-4000-8000-000000000002' LIMIT 1;
SELECT test_auth.assert((SELECT count(*)=2 AND count(DISTINCT payload->>'scope')=2 AND bool_and(payload IN ('{"scope":"notes"}'::jsonb,'{"scope":"notifications"}'::jsonb)) FROM realtime.messages),'notes and ticket-derived notifications both invalidate without row data');
DELETE FROM realtime.messages;
SELECT set_config('aida.workspace_sync_seen','{}',true);
UPDATE public.workspaces SET name=name WHERE id='20000000-0000-4000-8000-000000000002';
SELECT test_auth.assert((SELECT count(*)=1 AND bool_and(payload='{"scope":"access"}'::jsonb) FROM realtime.messages),'workspace configuration invalidates access without metadata');
DELETE FROM realtime.messages;
SELECT set_config('aida.workspace_sync_seen','{}',true);
SELECT set_config('aida.test_sync_send_failure','true',true);
UPDATE public.tickets SET tech_notes='SYNTHETIC SAVED DESPITE BROKER FAILURE' WHERE id=(SELECT id FROM public.tickets WHERE workspace_id='20000000-0000-4000-8000-000000000002' LIMIT 1);
SELECT test_auth.assert(EXISTS(SELECT 1 FROM public.tickets WHERE workspace_id='20000000-0000-4000-8000-000000000002' AND tech_notes='SYNTHETIC SAVED DESPITE BROKER FAILURE'),'broker failure does not roll back successful business write');
SELECT test_auth.assert((SELECT count(*)=0 FROM realtime.messages),'failed broker sends no partial event');
SELECT set_config('aida.test_sync_send_failure','false',true);
SELECT set_config('aida.workspace_sync_seen','{}',true);
SAVEPOINT before_rolled_back_write;
UPDATE public.inventory_items SET internal_notes='SYNTHETIC ROLLED BACK' WHERE workspace_id='20000000-0000-4000-8000-000000000002';
ROLLBACK TO SAVEPOINT before_rolled_back_write;
SELECT test_auth.assert((SELECT count(*)=0 FROM realtime.messages),'rolled back mutation rolls back its emitted hint');
ROLLBACK;
SELECT 'PASS: private workspace authorization, minimal payload, coalescing, outage and transaction rollback' AS result;
