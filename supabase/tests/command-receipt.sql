\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR inet_server_port()<>54329
    OR current_database() NOT LIKE 'aida_auth_review_%' THEN RAISE EXCEPTION 'Named loopback synthetic database required';END IF;
END $$;
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('95cb3619-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002',clock_timestamp());
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','95cb3619-0000-4000-8000-000000000002');
SELECT set_config('request.method','',true);
UPDATE public.workspaces SET tracker_config=coalesce(tracker_config,'{}'::jsonb)||'{"customization":{"modules":true,"workflow":true},"modules":{"inventory":true,"agenda":true},"workflow":{"parts_control":true}}'::jsonb WHERE id='20000000-0000-4000-8000-000000000002';
INSERT INTO public.inventory_items(id,workspace_id,name,sku,track_stock)
VALUES('95cb3619-0000-4000-8000-000000000010','20000000-0000-4000-8000-000000000002','COMMAND RECEIPT synthetic part','COMMAND-RECEIPT',false);
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,status,budget_status,technician_id,analysis_deadline,deadline,tech_notes)
SELECT ('95cb3619-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'20000000-0000-4000-8000-000000000002','Synthetic receipt fixture','COMMAND-RECEIPT-'||n,'Synthetic device','Synthetic defect',CASE WHEN n=22 THEN 'Analise Tecnica' ELSE 'Aprovacao' END,'Enviado',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),now()+interval '42 days',now()+interval '43 days','LOCAL DRAFT MUST NEVER BE REPLACED BY RECEIPT'
FROM generate_series(21,24)n;
CREATE TEMP TABLE command_receipts(name text PRIMARY KEY,payload jsonb NOT NULL);
GRANT ALL ON command_receipts TO authenticated;
CREATE FUNCTION test_auth.command_request(p_path text,p_ticket uuid,p_revision bigint) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
 PERFORM set_config('request.method',CASE WHEN p_path='/tickets' THEN 'PATCH' ELSE 'POST' END,true);
 PERFORM set_config('request.path',p_path,true);
 PERFORM set_config('request.headers',jsonb_build_object('x-workspace-id','20000000-0000-4000-8000-000000000002','x-aida-ticket-version',jsonb_build_object('id',p_ticket,'revision',p_revision)::text)::text,true);
 PERFORM set_config('aida.checked_ticket_versions','{}',true);
END $$;
SELECT test_auth.assert(NOT has_function_privilege('authenticated','private.ticket_command_receipt(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','private.assert_ticket_command_snapshot(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','private.ticket_command_receipt(uuid,uuid)','EXECUTE'),'private receipt helpers are unavailable to clients');
SELECT test_auth.assert((SELECT count(*)=2 AND bool_and(NOT prosecdef AND pg_get_userbyid(proowner)='postgres' AND proconfig=ARRAY['search_path=""']) FROM pg_proc WHERE oid IN('private.ticket_command_receipt(uuid,uuid)'::regprocedure,'private.assert_ticket_command_snapshot(uuid,uuid)'::regprocedure)),'receipt helpers preserve invoker security and empty search path');

-- Create appointment and then approve using exactly the version returned by that transaction.
SET LOCAL ROLE authenticated;
SELECT test_auth.command_request('/rpc/create_ticket_appointment','95cb3619-0000-4000-8000-000000000021',1);
INSERT INTO command_receipts VALUES('schedule',public.create_ticket_appointment('95cb3619-0000-4000-8000-000000000021',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'repair',(current_date+40+time '10:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+40+time '10:30') AT TIME ZONE 'America/Sao_Paulo','Synthetic command receipt'));
RESET ROLE;
SELECT test_auth.assert((SELECT (payload->>'ticket_revision')::bigint=t.revision AND t.revision>1 AND payload->>'ticket_id'=t.id::text FROM command_receipts c JOIN public.tickets t ON t.id='95cb3619-0000-4000-8000-000000000021' WHERE c.name='schedule'),'schedule receipt captures final ticket revision after all synchronous triggers');
SELECT test_auth.assert((SELECT payload->'ticket_updates'->>'repair_scheduled'='true' AND NOT(payload->'ticket_updates' ? 'tech_notes') FROM command_receipts WHERE name='schedule'),'schedule receipt contains confirmed workflow fields and no draft notes');
SET LOCAL ROLE authenticated;
SELECT test_auth.command_request('/tickets','95cb3619-0000-4000-8000-000000000021',(SELECT (payload->>'ticket_revision')::bigint FROM command_receipts WHERE name='schedule'));
UPDATE public.tickets SET status='Andamento Reparo',budget_status='Aprovado' WHERE id='95cb3619-0000-4000-8000-000000000021';
RESET ROLE;
SELECT test_auth.assert((SELECT status='Andamento Reparo' FROM public.tickets WHERE id='95cb3619-0000-4000-8000-000000000021'),'schedule then budget continuation succeeds with receipt version');
SET LOCAL ROLE authenticated;
SELECT test_auth.command_request('/tickets','95cb3619-0000-4000-8000-000000000021',(SELECT (payload->>'ticket_revision')::bigint FROM command_receipts WHERE name='schedule'));
SELECT test_auth.expect_error($q$UPDATE public.tickets SET priority='Urgente' WHERE id='95cb3619-0000-4000-8000-000000000021'$q$,'PT409');
RESET ROLE;

-- Parts registration also changes the parent ticket. Continue from its own receipt, not a fresh GET.
SET LOCAL ROLE authenticated;
SELECT test_auth.command_request('/rpc/request_ticket_inventory_parts','95cb3619-0000-4000-8000-000000000022',1);
INSERT INTO command_receipts VALUES('parts',public.request_ticket_inventory_parts('95cb3619-0000-4000-8000-000000000022','[{"item_id":"95cb3619-0000-4000-8000-000000000010","quantity":1}]','analysis',false));
RESET ROLE;
SELECT test_auth.assert((SELECT (payload->>'ticket_revision')::bigint=t.revision AND t.revision>1 AND payload->'ticket_updates'->>'parts_needed'=t.parts_needed AND NOT(payload->'ticket_updates' ? 'tech_notes') FROM command_receipts c JOIN public.tickets t ON t.id='95cb3619-0000-4000-8000-000000000022' WHERE c.name='parts'),'parts receipt captures confirmed summary and final revision without replacing draft');
SET LOCAL ROLE authenticated;
SELECT test_auth.command_request('/tickets','95cb3619-0000-4000-8000-000000000022',(SELECT (payload->>'ticket_revision')::bigint FROM command_receipts WHERE name='parts'));
UPDATE public.tickets SET status='Aprovacao',tech_notes='LOCAL DRAFT SUBMITTED AFTER PARTS' WHERE id='95cb3619-0000-4000-8000-000000000022';
RESET ROLE;
SELECT test_auth.assert((SELECT status='Aprovacao' AND tech_notes='LOCAL DRAFT SUBMITTED AFTER PARTS' FROM public.tickets WHERE id='95cb3619-0000-4000-8000-000000000022'),'parts then analysis continuation succeeds without accidental old revision');

-- A no-op approval is still forbidden from silently adopting a different snapshot.
SELECT set_config('request.method','',true);
UPDATE public.tickets SET priority='Alta' WHERE id='95cb3619-0000-4000-8000-000000000023';
SET LOCAL ROLE authenticated;
SELECT test_auth.command_request('/rpc/approve_ticket_with_inventory','95cb3619-0000-4000-8000-000000000023',1);
SELECT test_auth.expect_error($q$SELECT public.approve_ticket_with_inventory('95cb3619-0000-4000-8000-000000000023')$q$,'PT409');
SELECT test_auth.command_request('/rpc/approve_ticket_with_inventory','95cb3619-0000-4000-8000-000000000023',2);
INSERT INTO command_receipts VALUES('no_op',public.approve_ticket_with_inventory('95cb3619-0000-4000-8000-000000000023'));
SELECT test_auth.assert((SELECT payload->>'route'='no_inventory_parts' AND (payload->>'ticket_revision')::bigint=2 FROM command_receipts WHERE name='no_op'),'validated no-op approval returns its unchanged own snapshot');
RESET ROLE;
SELECT test_auth.assert((SELECT revision=2 FROM public.tickets WHERE id='95cb3619-0000-4000-8000-000000000023'),'stale and validated no-op neither mutate ticket');

-- A stale create must not leave an appointment or log behind.
SELECT set_config('request.method','',true);
UPDATE public.tickets SET priority='Alta' WHERE id='95cb3619-0000-4000-8000-000000000024';
SET LOCAL ROLE authenticated;
SELECT test_auth.command_request('/rpc/create_ticket_appointment','95cb3619-0000-4000-8000-000000000024',1);
SELECT test_auth.expect_error($q$SELECT public.create_ticket_appointment('95cb3619-0000-4000-8000-000000000024',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'repair',(current_date+41+time '10:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+41+time '10:30') AT TIME ZONE 'America/Sao_Paulo','stale create')$q$,'PT409');
RESET ROLE;
SELECT test_auth.assert(NOT EXISTS(SELECT 1 FROM public.ticket_appointments WHERE ticket_id='95cb3619-0000-4000-8000-000000000024') AND NOT EXISTS(SELECT 1 FROM public.ticket_logs WHERE ticket_id='95cb3619-0000-4000-8000-000000000024' AND action='Agendou Reparo'),'stale scheduling rolls back every appointment and audit side effect');
ROLLBACK;
SELECT 'PASS: command receipts, exact version continuations, stale/no-op checks and minimal workflow fields' AS result;
