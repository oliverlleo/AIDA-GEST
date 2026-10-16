-- Read/write only in the isolated local synthetic test database; never production.
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Local SQL tests require loopback PostgreSQL'; END IF; END $$;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT set_config('request.method','POST',true),set_config('request.path','/tickets',true);
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,status,revision,technician_id)
VALUES('6f000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','Concurrency fixture','REVISION_LOCAL_FIXTURE','Test device','Test defect',now()+interval '2 days',now()+interval '3 days','Aberto',999,(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'));
SELECT test_auth.assert((SELECT revision=1 FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'),'insert ignores browser revision');
SELECT set_config('request.method','PATCH',true);
SELECT test_auth.expect_error($q$UPDATE public.tickets SET tech_notes='missing version' WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
SELECT set_config('request.headers','{"x-workspace-id":"20000000-0000-4000-8000-000000000002","x-aida-ticket-version":"not-json"}',true);
SELECT test_auth.expect_error($q$UPDATE public.tickets SET tech_notes='invalid version' WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
SELECT set_config('request.headers',jsonb_build_object('x-workspace-id','20000000-0000-4000-8000-000000000002','x-aida-ticket-version','{"id":"6f000000-0000-4000-8000-000000000001","revision":"1"}')::text,true);
SELECT test_auth.expect_error($q$UPDATE public.tickets SET revision=888 WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'42501');
UPDATE public.tickets SET tech_notes='first committed edit' WHERE id='6f000000-0000-4000-8000-000000000001';
SELECT test_auth.assert((SELECT revision=2 AND tech_notes='first committed edit' FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'),'server increments and saves valid version');
-- A second server-side update in the same transaction may be derived by triggers.
UPDATE public.tickets SET priority_requested=true WHERE id='6f000000-0000-4000-8000-000000000001';
SELECT test_auth.assert((SELECT revision=3 FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'),'derived transaction writes increment without stale self-conflict');
-- Emulate the next HTTP transaction by clearing only the transaction guard.
SELECT set_config('aida.checked_ticket_versions','{}',true);
SELECT test_auth.expect_error($q$UPDATE public.tickets SET tech_notes='stale browser overwrite' WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
SELECT test_auth.assert((SELECT revision=3 AND tech_notes='first committed edit' FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'),'stale browser cannot overwrite');
SELECT set_config('request.headers',jsonb_build_object('x-workspace-id','20000000-0000-4000-8000-000000000002','x-aida-ticket-version','{"id":"6f000000-0000-4000-8000-000000000099","revision":"3"}')::text,true);
SELECT test_auth.expect_error($q$UPDATE public.tickets SET tech_notes='wrong ticket header' WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
SELECT set_config('request.method','POST',true),set_config('request.path','/rpc/unlisted_future_function',true);
SELECT set_config('request.headers','{"x-workspace-id":"20000000-0000-4000-8000-000000000002"}',true);
SELECT test_auth.expect_error($q$UPDATE public.tickets SET tech_notes='unlisted RPC escape' WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
-- A spoofed known path does not exempt a direct authenticated SQL write.
SELECT set_config('request.path','/rpc/start_ticket_analysis',true);
SELECT test_auth.expect_error($q$UPDATE public.tickets SET tech_notes='spoofed RPC escape' WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
SELECT set_config('request.method','PATCH',true),set_config('request.path','/tickets',true);
SELECT set_config('request.headers',jsonb_build_object('x-workspace-id','20000000-0000-4000-8000-000000000002','x-aida-ticket-version','{"id":"6f000000-0000-4000-8000-000000000001","revision":"3"}')::text,true);
UPDATE public.tickets SET status='Analise Tecnica' WHERE id='6f000000-0000-4000-8000-000000000001';
SELECT set_config('aida.checked_ticket_versions','{}',true);
SELECT set_config('request.method','POST',true),set_config('request.path','/rpc/start_ticket_analysis',true);
SELECT set_config('request.headers','{"x-workspace-id":"20000000-0000-4000-8000-000000000002"}',true);
SELECT public.start_ticket_analysis('6f000000-0000-4000-8000-000000000001');
SELECT test_auth.assert((SELECT revision=5 AND analysis_started_at IS NOT NULL FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'),'audited state machine increments without browser version');
SELECT test_auth.expect_error($q$SELECT public.start_ticket_analysis('6f000000-0000-4000-8000-000000000001')$q$);
SELECT test_auth.assert((SELECT count(*)=1 FROM public.ticket_logs WHERE ticket_id='6f000000-0000-4000-8000-000000000001' AND action='Iniciou Análise'),'state machine repeat emits one effect/log');
SELECT set_config('aida.checked_ticket_versions','{}',true);
SELECT set_config('request.method','DELETE',true),set_config('request.path','/tickets',true);
SELECT test_auth.expect_error($q$DELETE FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
SELECT set_config('request.headers',jsonb_build_object('x-workspace-id','20000000-0000-4000-8000-000000000002','x-aida-ticket-version','{"id":"6f000000-0000-4000-8000-000000000001","revision":"4"}')::text,true);
SELECT test_auth.expect_error($q$DELETE FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'$q$,'PT409');
SELECT test_auth.assert((SELECT revision=5 FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'),'missing or stale DELETE cannot remove the OS');
SELECT set_config('request.method','PATCH',true),set_config('request.path','/tickets',true);
SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000001');
UPDATE public.tickets SET tech_notes='wrong tenant attempt' WHERE id='6f000000-0000-4000-8000-000000000001';
SELECT test_auth.assert(NOT EXISTS(SELECT 1 FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000001'),'revision does not grant cross-tenant visibility');
ROLLBACK;
SELECT 'PASS: revision guard, malformed/stale/spoofed versions, atomic internal updates, state machine and tenant isolation' AS result;
