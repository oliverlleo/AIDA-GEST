\set ON_ERROR_STOP on
BEGIN;
\ir operation-concurrency-fixtures.sql
CREATE FUNCTION test_auth.operation_request(p_path text,p_resource text DEFAULT NULL,p_id uuid DEFAULT NULL,p_revision text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_headers jsonb:=jsonb_build_object('x-workspace-id','20000000-0000-4000-8000-000000000002');
BEGIN
 IF p_resource IS NOT NULL THEN v_headers:=v_headers||jsonb_build_object('x-aida-operation-version',jsonb_build_object('resource',p_resource,'id',p_id,'revision',p_revision)::text);END IF;
 PERFORM set_config('request.headers',v_headers::text,true);
 PERFORM set_config('request.path',p_path,true);
 PERFORM set_config('request.method','POST',true);
 PERFORM set_config('aida.checked_operation_versions','{}',true);
 PERFORM set_config('aida.checked_ticket_versions','{}',true);
END $$;
SELECT test_auth.assert((SELECT count(*)=2 FROM pg_trigger WHERE tgname='zzzz_aida_operation_revision' AND NOT tgisinternal),'two operation revision triggers');
SELECT test_auth.assert((SELECT NOT prosecdef AND proconfig=ARRAY['search_path=""'] FROM pg_proc WHERE oid='private.enforce_operation_revision()'::regprocedure),'operation trigger uses invoker and pinned search path');
SELECT test_auth.assert(NOT has_function_privilege('authenticated','private.enforce_operation_revision()','EXECUTE') AND NOT has_function_privilege('anon','private.enforce_operation_revision()','EXECUTE'),'clients cannot call trigger function');
SET LOCAL ROLE authenticated;
SELECT test_auth.assert((public.get_inventory_purchase_detail('94cb3619-0000-4000-8000-000000000012')->'purchase'->>'revision')::bigint=1,'purchase DTO exposes initial server revision');
SELECT test_auth.assert((public.get_ticket_appointments('94cb3619-0000-4000-8000-000000000020')->0->>'revision')::bigint=1,'ticket appointment DTO exposes revision');
SELECT test_auth.assert((public.get_technician_schedule((SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'day',current_date+30)->'appointments'->0->>'revision')::bigint=1,'schedule DTO exposes revision');
SELECT test_auth.operation_request('/rpc/receive_inventory_purchase');
SELECT test_auth.expect_error($q$SELECT public.receive_inventory_purchase('94cb3619-0000-4000-8000-000000000012','[{"purchase_item_id":"94cb3619-0000-4000-8000-000000000013","quantity":2,"unit_cost":2,"destination":"stock","location_id":"94cb3619-0000-4000-8000-000000000011"}]',false)$q$,'PT409');
SELECT test_auth.operation_request('/rpc/receive_inventory_purchase','ticket_appointments','94cb3619-0000-4000-8000-000000000021','1');
SELECT test_auth.expect_error($q$SELECT public.receive_inventory_purchase('94cb3619-0000-4000-8000-000000000012','[{"purchase_item_id":"94cb3619-0000-4000-8000-000000000013","quantity":2,"unit_cost":2,"destination":"stock","location_id":"94cb3619-0000-4000-8000-000000000011"}]',false)$q$,'PT409');
SELECT test_auth.operation_request('/rpc/receive_inventory_purchase','inventory_purchases','94cb3619-0000-4000-8000-000000000012','1');
SELECT public.receive_inventory_purchase('94cb3619-0000-4000-8000-000000000012','[{"purchase_item_id":"94cb3619-0000-4000-8000-000000000013","quantity":2,"unit_cost":2,"destination":"stock","location_id":"94cb3619-0000-4000-8000-000000000011"}]',false);
SELECT test_auth.assert((public.get_inventory_purchase_detail('94cb3619-0000-4000-8000-000000000012')->'purchase'->>'revision')::bigint=2,'successful partial receipt increments purchase revision');
SELECT test_auth.operation_request('/rpc/receive_inventory_purchase','inventory_purchases','94cb3619-0000-4000-8000-000000000012','1');
SELECT test_auth.expect_error($q$SELECT public.receive_inventory_purchase('94cb3619-0000-4000-8000-000000000012','[{"purchase_item_id":"94cb3619-0000-4000-8000-000000000013","quantity":2,"unit_cost":2,"destination":"stock","location_id":"94cb3619-0000-4000-8000-000000000011"}]',false)$q$,'PT409');
RESET ROLE;
SELECT test_auth.assert((SELECT received_quantity=2 FROM public.inventory_purchase_items WHERE id='94cb3619-0000-4000-8000-000000000013'),'stale receipt leaves received quantity unchanged');
SELECT test_auth.assert((SELECT physical_quantity=2 FROM public.inventory_balances WHERE item_id='94cb3619-0000-4000-8000-000000000010' AND location_id='94cb3619-0000-4000-8000-000000000011'),'stale receipt rolls back stock side effects');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.inventory_movements WHERE purchase_id='94cb3619-0000-4000-8000-000000000012'),'stale receipt leaves only one movement');
SET LOCAL ROLE authenticated;
SELECT test_auth.operation_request('/rpc/reschedule_ticket_appointment');
SELECT test_auth.expect_error($q$SELECT public.reschedule_ticket_appointment('94cb3619-0000-4000-8000-000000000021',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),(current_date+30+time '11:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+30+time '11:30') AT TIME ZONE 'America/Sao_Paulo','missing revision')$q$,'PT409');
SELECT test_auth.operation_request('/rpc/reschedule_ticket_appointment','ticket_appointments','94cb3619-0000-4000-8000-000000000021','1');
SELECT public.reschedule_ticket_appointment('94cb3619-0000-4000-8000-000000000021',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),(current_date+30+time '11:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+30+time '11:30') AT TIME ZONE 'America/Sao_Paulo','first reschedule');
SELECT test_auth.operation_request('/rpc/reschedule_ticket_appointment','ticket_appointments','94cb3619-0000-4000-8000-000000000021','1');
SELECT test_auth.expect_error($q$SELECT public.reschedule_ticket_appointment('94cb3619-0000-4000-8000-000000000021',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),(current_date+30+time '12:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+30+time '12:30') AT TIME ZONE 'America/Sao_Paulo','stale reschedule')$q$,'PT409');
RESET ROLE;
SELECT test_auth.assert((SELECT revision=2 AND scheduled_start=(current_date+30+time '11:00') AT TIME ZONE 'America/Sao_Paulo' FROM public.ticket_appointments WHERE id='94cb3619-0000-4000-8000-000000000021'),'stale reschedule cannot overwrite first saved schedule');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.ticket_logs WHERE ticket_id='94cb3619-0000-4000-8000-000000000020' AND action='Remarcou Análise'),'stale reschedule does not duplicate audit log');
SELECT test_auth.operation_request('/inventory_purchases','inventory_purchases','94cb3619-0000-4000-8000-000000000012','1');
SELECT set_config('request.method','PATCH',true);
SELECT test_auth.expect_error($q$UPDATE public.inventory_purchases SET notes='stale direct write' WHERE id='94cb3619-0000-4000-8000-000000000012'$q$,'PT409');
SELECT test_auth.expect_error($q$UPDATE public.inventory_purchases SET revision=99 WHERE id='94cb3619-0000-4000-8000-000000000012'$q$,'42501');
SELECT test_auth.operation_request('/rpc/other_internal_command');
UPDATE public.inventory_purchases SET notes='legitimate internal command' WHERE id='94cb3619-0000-4000-8000-000000000012';
SELECT test_auth.assert((SELECT revision=3 FROM public.inventory_purchases WHERE id='94cb3619-0000-4000-8000-000000000012'),'internal command without client form advances version');
ROLLBACK;
SELECT 'PASS: stale purchase receipts, appointment edits, DTO versions and side effect rollback' AS result;
