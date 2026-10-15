-- Current-row assignment and role unions. All actions roll back on synthetic fixtures.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Loopback required'; END IF; END $$;
CREATE TEMP TABLE audit_multirole_result(test text, result jsonb);
GRANT SELECT, INSERT ON audit_multirole_result TO authenticated;
CREATE FUNCTION pg_temp.observe_multi(p_test text,p_sql text,p_expected text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_rows bigint:=0; v_state text; v_message text; v_result jsonb;
BEGIN
  BEGIN
    EXECUTE p_sql; GET DIAGNOSTICS v_rows=ROW_COUNT;
    v_result:=jsonb_build_object('allowed',true,'rows',v_rows);
    RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='probe rollback';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
  WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
    v_result:=jsonb_build_object('allowed',false,'sqlstate',v_state,'message',v_message);
  END;
  IF p_expected='denied' THEN
    IF COALESCE((v_result->>'allowed')::boolean,false) AND COALESCE((v_result->>'rows')::bigint,0)>0 THEN RAISE EXCEPTION 'Unauthorized success: % / %',p_test,v_result; END IF;
  ELSIF v_result IS DISTINCT FROM jsonb_build_object('allowed',true,'rows',p_expected::bigint) THEN RAISE EXCEPTION 'Legitimate action failed: % / %',p_test,v_result; END IF;
  INSERT INTO audit_multirole_result VALUES(p_test,v_result||jsonb_build_object('pass',true,'expected',p_expected));
END $$;
SET ROLE authenticated;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.update_workspace_tracker_config(jsonb_set(COALESCE((SELECT tracker_config FROM public.workspaces WHERE id='20000000-0000-4000-8000-000000000002'),'{}'::jsonb),'{test_flow}','"tester"'::jsonb));
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status,repair_start_at)
VALUES('50000000-0000-4000-8000-000000000008','20000000-0000-4000-8000-000000000002','Synthetic other repair','FULL_MULTI_8','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='owner_employee'),'Andamento Reparo','Aprovado',now());
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status,repair_start_at,repair_end_at,repair_successful,test_start_at)
VALUES('50000000-0000-4000-8000-000000000009','20000000-0000-4000-8000-000000000002','Synthetic other final test','FULL_MULTI_9','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='owner_employee'),'Teste Final','Aprovado',now()-interval '1 hour',now()-interval '30 minutes',true,now()-interval '5 minutes');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status,repair_start_at)
VALUES('50000000-0000-4000-8000-000000000010','20000000-0000-4000-8000-000000000002','Synthetic own repair','FULL_MULTI_10','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Andamento Reparo','Aprovado',now());
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status)
VALUES('50000000-0000-4000-8000-000000000018','20000000-0000-4000-8000-000000000002','Synthetic own pending repair','FULL_MULTI_18','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Andamento Reparo','Aprovado');
INSERT INTO public.outsourced_companies(id,workspace_id,name) VALUES('71000000-0000-4000-8000-000000000011','20000000-0000-4000-8000-000000000002','Synthetic outsourced security partner');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status,is_outsourced,outsourced_company_id,outsourced_return_count,outsourced_notes,test_start_at)
VALUES('50000000-0000-4000-8000-000000000011','20000000-0000-4000-8000-000000000002','Synthetic outsourced client','FULL_MULTI_11','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',NULL,'Teste Final','Aprovado',true,'71000000-0000-4000-8000-000000000011',1,'[{"text":"Synthetic prior return","user":"Synthetic prior actor"}]',now()-interval '5 minutes');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Synthetic technician tester',ARRAY['tecnico','tester']);
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('tech tester technical note OTHER technician OS',$$UPDATE public.tickets SET tech_notes='FORGED_DIAGNOSIS' WHERE id='50000000-0000-4000-8000-000000000003'$$,'denied');
SELECT pg_temp.observe_multi('tech tester technical repair timer OTHER technician OS',$$UPDATE public.tickets SET repair_start_at=now()+interval '1 second' WHERE id='50000000-0000-4000-8000-000000000003'$$,'denied');
SELECT pg_temp.observe_multi('tech tester final test notes OTHER technician OS legitimate',$$UPDATE public.tickets SET test_notes='[{"synthetic":"test"}]'::jsonb WHERE id='50000000-0000-4000-8000-000000000003'$$,'1');
SELECT pg_temp.observe_multi('tech tester direct handoff blocked; approved RPC handles it',$$UPDATE public.tickets SET status='Andamento Reparo',previous_status='Teste Final',repair_start_at=NULL,test_start_at=NULL,test_notes='[{"synthetic":"failure"}]'::jsonb WHERE id='50000000-0000-4000-8000-000000000003'$$,'denied');
SELECT pg_temp.observe_multi('tech tester own technical notes preserved',$$UPDATE public.tickets SET tech_notes='Synthetic own diagnosis' WHERE id='50000000-0000-4000-8000-000000000005'$$,'1');
SELECT pg_temp.observe_multi('tech tester own repair start RPC preserved',$$SELECT test_auth.assert((public.start_repair_timer('50000000-0000-4000-8000-000000000018')->>'success')::boolean,'own repair start RPC')$$,'1');
SELECT pg_temp.observe_multi('tech tester legitimate failed-test RPC',$$SELECT test_auth.assert((public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Andamento Reparo',jsonb_build_object('deadline',now()+interval '3 days','priority','Normal','repair_start_at',NULL,'test_start_at',NULL,'test_notes',jsonb_build_array(jsonb_build_object('text','Synthetic failed test','user','FORGED_ACTOR'))))->>'status')='Andamento Reparo','RPC completed tester handoff')$$,'1');
SELECT pg_temp.observe_multi('tech tester forbidden technical note via test RPC',$$SELECT public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Retirada Cliente','{"tech_notes":"FORGED_DIAGNOSIS"}')$$,'denied');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Synthetic technician attendant',ARRAY['tecnico','atendente']);
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('tech attendant repair timer OTHER technician OS',$$UPDATE public.tickets SET repair_start_at=now()+interval '1 second' WHERE id='50000000-0000-4000-8000-000000000008'$$,'denied');
SELECT pg_temp.observe_multi('tech attendant repair completion OTHER technician OS',$$UPDATE public.tickets SET status='Teste Final',previous_status='Andamento Reparo',repair_successful=true,repair_end_at=now() WHERE id='50000000-0000-4000-8000-000000000008'$$,'denied');
SELECT pg_temp.observe_multi('tech attendant own repair start RPC preserved',$$SELECT test_auth.assert((public.start_repair_timer('50000000-0000-4000-8000-000000000018')->>'success')::boolean,'own repair start RPC')$$,'1');
SELECT pg_temp.observe_multi('tech attendant own repair completion RPC preserved',$$SELECT test_auth.assert((public.complete_repair_with_timer('50000000-0000-4000-8000-000000000010',true)->>'success')::boolean,'own repair completion RPC')$$,'1');
SELECT pg_temp.observe_multi('tech attendant other repair start RPC denied',$$SELECT public.start_repair_timer('50000000-0000-4000-8000-000000000008')$$,'denied');
SELECT pg_temp.observe_multi('tech attendant other repair completion RPC denied',$$SELECT public.complete_repair_with_timer('50000000-0000-4000-8000-000000000008',true)$$,'denied');
SELECT pg_temp.observe_multi('tech attendant tester-mode conclusion without tester denied',$$SELECT public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Retirada Cliente','{}')$$,'denied');
SELECT test_auth.login(5,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('tester sets repair start clock instead of reset',$$UPDATE public.tickets SET repair_start_at=now()+interval '1 second' WHERE id='50000000-0000-4000-8000-000000000003'$$,'denied');
SELECT pg_temp.observe_multi('tester direct SQL RETURNING handoff blocked; approved RPC handles it',$$UPDATE public.tickets SET status='Andamento Reparo',previous_status='Teste Final',repair_start_at=NULL,test_start_at=NULL,test_notes='[{"synthetic":"failure"}]'::jsonb WHERE id='50000000-0000-4000-8000-000000000003' RETURNING id$$,'denied');
SELECT pg_temp.observe_multi('tester approved test RPC succeeds',$$SELECT test_auth.assert((public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Retirada Cliente','{"checklist_final_data":[{"item":"Synthetic check","ok":true}]}')->>'status')='Retirada Cliente','RPC approved final test')$$,'1');
SELECT pg_temp.observe_multi('tester failed-test RPC succeeds',$$SELECT test_auth.assert((public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Andamento Reparo',jsonb_build_object('deadline',now()+interval '3 days','priority','Normal','repair_start_at',NULL,'test_start_at',NULL,'test_notes',jsonb_build_array(jsonb_build_object('text','Synthetic failed test','user','FORGED_ACTOR'))))->>'status')='Andamento Reparo','RPC returned to repair')$$,'1');
SELECT pg_temp.observe_multi('tester fake admin claim in test payload denied',$$SELECT public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Retirada Cliente','{"is_admin":true,"roles":["admin"]}')$$,'denied');
SELECT pg_temp.observe_multi('tester forged budget in test payload denied',$$SELECT public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Retirada Cliente','{"budget_status":"Aprovado","budget_value":1}')$$,'denied');
SELECT pg_temp.observe_multi('tester normal OS cannot be sent to outsourced provider',$$SELECT public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Terceirizado',jsonb_build_object('outsourced_deadline',now()+interval '3 days','outsourced_notes',jsonb_build_array(jsonb_build_object('text','Synthetic failure'))))$$,'denied');
SELECT pg_temp.observe_multi('tester invalid conclusion status denied',$$SELECT public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Finalizado','{}')$$,'denied');
SELECT pg_temp.observe_multi('tester other-company target denied',$$SELECT public.conclude_ticket_test('50000000-0000-4000-8000-000000000004','Retirada Cliente','{}')$$,'denied');
SAVEPOINT outsourced_server_metadata;
SELECT test_auth.assert((public.conclude_ticket_test('50000000-0000-4000-8000-000000000011','Terceirizado',jsonb_build_object('outsourced_deadline',now()+interval '4 days','outsourced_return_count',999,'test_start_at',NULL,'outsourced_notes',jsonb_build_array(jsonb_build_object('text','Synthetic outsourced test failure','user','FORGED_ACTOR','context','FORGED_CONTEXT'))))->>'status')='Terceirizado','RPC returned outsourced test to partner');
RESET ROLE;
SELECT test_auth.assert((SELECT status='Terceirizado' AND outsourced_return_count=2 AND jsonb_array_length(outsourced_notes)=2 AND outsourced_notes->-1->>'text'='Synthetic outsourced test failure' AND outsourced_notes->-1->>'user'=(SELECT name FROM public.employees WHERE id=(SELECT id FROM test_auth.fixture WHERE name='tester_employee')) AND outsourced_notes->-1->>'context'='Retorno 2x' AND test_start_at IS NULL FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000011'),'server derives return counter, actor and context; preserves prior history');
ROLLBACK TO SAVEPOINT outsourced_server_metadata;
RELEASE SAVEPOINT outsourced_server_metadata;
INSERT INTO audit_multirole_result VALUES('tester outsourced return RPC derives counter and actor',jsonb_build_object('allowed',true,'rows',1,'pass',true,'expected','1','server_counter_validated',true,'server_actor_validated',true));
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='tester_employee'),'Synthetic tester attendant',ARRAY['tester','atendente']);
SELECT test_auth.login(5,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('tester attendant direct handoff blocked; approved RPC handles it',$$UPDATE public.tickets SET status='Andamento Reparo',previous_status='Teste Final',repair_start_at=NULL,test_start_at=NULL,test_notes='[{"synthetic":"failure"}]'::jsonb WHERE id='50000000-0000-4000-8000-000000000009'$$,'denied');

SELECT pg_temp.observe_multi('tester attendant failed-test RPC preserved',$$SELECT test_auth.assert((public.conclude_ticket_test('50000000-0000-4000-8000-000000000009','Andamento Reparo',jsonb_build_object('deadline',now()+interval '3 days','priority','Normal','repair_start_at',NULL,'test_start_at',NULL,'test_notes',jsonb_build_array(jsonb_build_object('text','Synthetic failed test'))))->>'status')='Andamento Reparo','tester attendant RPC handoff')$$,'1');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Synthetic technical-only employee',ARRAY['tecnico']);
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status)
VALUES('50000000-0000-4000-8000-000000000012','20000000-0000-4000-8000-000000000002','Synthetic own open client','FULL_MULTI_12','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Aberto','Pendente');
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('technical own open-to-outsourced partner transition preserved',$$UPDATE public.tickets SET status='Terceirizado',previous_status='Aberto',is_outsourced=true,outsourced_company_id='71000000-0000-4000-8000-000000000011',outsourced_at=now() WHERE id='50000000-0000-4000-8000-000000000012'$$,'1');
SELECT pg_temp.observe_multi('technical partner change outside authorized transition denied',$$UPDATE public.tickets SET is_outsourced=true,outsourced_company_id='71000000-0000-4000-8000-000000000011' WHERE id='50000000-0000-4000-8000-000000000010'$$,'denied');
SELECT pg_temp.observe_multi('technical approved-budget repair insertion denied',$$INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,deadline,technician_id,status,budget_status) VALUES('50000000-0000-4000-8000-000000000013','20000000-0000-4000-8000-000000000002','Synthetic approved new client','FULL_MULTI_13','Synthetic device','Synthetic defect',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Andamento Reparo','Aprovado')$$,'denied');
SELECT pg_temp.observe_multi('technical approved-budget initial insertion denied',$$INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status) VALUES('50000000-0000-4000-8000-000000000013','20000000-0000-4000-8000-000000000002','Synthetic approved initial client','FULL_MULTI_13','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Aberto','Aprovado')$$,'denied');
SELECT pg_temp.observe_multi('technical own normal pending insertion preserved',$$INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status) VALUES('50000000-0000-4000-8000-000000000013','20000000-0000-4000-8000-000000000002','Synthetic normal new client','FULL_MULTI_13','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Aberto','Pendente')$$,'1');
SELECT test_auth.login(4,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('attendant approved-budget repair insertion preserved',$$INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,deadline,technician_id,status,budget_status) VALUES('50000000-0000-4000-8000-000000000013','20000000-0000-4000-8000-000000000002','Synthetic approved new client','FULL_MULTI_13','Synthetic device','Synthetic defect',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Andamento Reparo','Aprovado')$$,'1');

SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,priority,priority_requested,test_start_at)
VALUES('50000000-0000-4000-8000-000000000015','20000000-0000-4000-8000-000000000002','Synthetic tester limits','FULL_MULTI_15','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='owner_employee'),'Teste Final','Normal',false,now()-interval '1 minute');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status)
VALUES('50000000-0000-4000-8000-000000000016','20000000-0000-4000-8000-000000000002','Synthetic own approval','FULL_MULTI_16','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Aprovacao','Pendente');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='tester_employee'),'Synthetic pure tester',ARRAY['tester']);
SELECT public.update_workspace_tracker_config(jsonb_set(COALESCE((SELECT tracker_config FROM public.workspaces WHERE id='20000000-0000-4000-8000-000000000002'),'{}'::jsonb),'{test_flow}','"kanban"'::jsonb));
SELECT test_auth.login(5,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('kanban pure tester start-test denied',$$UPDATE public.tickets SET test_start_at=now() WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT pg_temp.observe_multi('kanban pure tester test notes denied',$$UPDATE public.tickets SET test_notes='[{"text":"Synthetic unauthorized test"}]' WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT pg_temp.observe_multi('kanban pure tester final checklist denied',$$UPDATE public.tickets SET checklist_final_data='[{"item":"Synthetic check","ok":true}]' WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT public.update_workspace_tracker_config(jsonb_set(COALESCE((SELECT tracker_config FROM public.workspaces WHERE id='20000000-0000-4000-8000-000000000002'),'{}'::jsonb),'{test_flow}','"tester"'::jsonb));
SELECT test_auth.login(5,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('tester mode pure tester start-test preserved',$$UPDATE public.tickets SET test_start_at=now() WHERE id='50000000-0000-4000-8000-000000000015'$$,'1');
SELECT pg_temp.observe_multi('tester mode pure tester test notes preserved',$$UPDATE public.tickets SET test_notes='[{"text":"Synthetic authorized test"}]' WHERE id='50000000-0000-4000-8000-000000000015'$$,'1');
SELECT pg_temp.observe_multi('tester mode pure tester final checklist preserved',$$UPDATE public.tickets SET checklist_final_data='[{"item":"Synthetic check","ok":true}]' WHERE id='50000000-0000-4000-8000-000000000015'$$,'1');
SELECT pg_temp.observe_multi('tester legitimate priority-request flag preserved',$$UPDATE public.tickets SET priority_requested=true WHERE id='50000000-0000-4000-8000-000000000015'$$,'1');
SELECT pg_temp.observe_multi('tester same-stage actual priority change denied',$$UPDATE public.tickets SET priority='Urgente' WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT pg_temp.observe_multi('tester same-stage actual deadline change denied',$$UPDATE public.tickets SET deadline=now()+interval '10 days' WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT pg_temp.observe_multi('tester same-stage outsourced counter change denied',$$UPDATE public.tickets SET outsourced_return_count=99 WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT pg_temp.observe_multi('tester same-stage outsourced notes change denied',$$UPDATE public.tickets SET outsourced_notes='[{"text":"Synthetic forged result","user":"FORGED_ACTOR"}]' WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT pg_temp.observe_multi('tester same-stage outsourced deadline change denied',$$UPDATE public.tickets SET outsourced_deadline=now()+interval '20 days' WHERE id='50000000-0000-4000-8000-000000000015'$$,'denied');
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.observe_multi('own technician direct repair clock in approval denied',$$UPDATE public.tickets SET repair_start_at=now() WHERE id='50000000-0000-4000-8000-000000000016'$$,'denied');
SELECT pg_temp.observe_multi('own technician direct analysis clock in approval denied',$$UPDATE public.tickets SET analysis_started_at=now() WHERE id='50000000-0000-4000-8000-000000000016'$$,'denied');
SELECT pg_temp.observe_multi('own technician direct skip not-started repair to test denied',$$UPDATE public.tickets SET status='Teste Final' WHERE id='50000000-0000-4000-8000-000000000018'$$,'denied');
SELECT pg_temp.observe_multi('own technician direct skip not-started repair to pickup denied',$$UPDATE public.tickets SET status='Retirada Cliente' WHERE id='50000000-0000-4000-8000-000000000018'$$,'denied');
SELECT pg_temp.observe_multi('own technician completion RPC requires start first',$$SELECT public.complete_repair_with_timer('50000000-0000-4000-8000-000000000018',true)$$,'denied');

-- Maintenance setup only; all workflow actions below execute as the real employee.
RESET ROLE;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO public.inventory_locations(id,workspace_id,name,normalized_address)
VALUES('72000000-0000-4000-8000-000000000019','20000000-0000-4000-8000-000000000002','Synthetic authorization shelf','AUTH-FULL-19');
INSERT INTO public.inventory_items(id,workspace_id,name,track_stock,default_location_id)
VALUES('73000000-0000-4000-8000-000000000019','20000000-0000-4000-8000-000000000002','Synthetic tracked repair component',true,'72000000-0000-4000-8000-000000000019');
INSERT INTO public.inventory_balances(workspace_id,item_id,location_id,physical_quantity)
VALUES('20000000-0000-4000-8000-000000000002','73000000-0000-4000-8000-000000000019','72000000-0000-4000-8000-000000000019',5);
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,deadline,technician_id,status,budget_status,repair_start_at)
VALUES('50000000-0000-4000-8000-000000000019','20000000-0000-4000-8000-000000000002','Synthetic inventory repair','FULL_MULTI_19','Synthetic device','Synthetic defect',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Andamento Reparo','Aprovado',now()-interval '2 minutes');
SET ROLE authenticated;
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.assert((public.request_ticket_inventory_parts('50000000-0000-4000-8000-000000000019','[{"item_id":"73000000-0000-4000-8000-000000000019","quantity":2}]','repair',true)->>'fully_reserved')::boolean,'real request RPC reserves synthetic stock');
SELECT pg_temp.observe_multi('own technician timer cannot bypass active inventory consumption',$$SELECT public.complete_repair_with_timer('50000000-0000-4000-8000-000000000019',true)$$,'denied');
SAVEPOINT inventory_real_completion;
SELECT test_auth.assert((public.complete_repair_with_inventory('50000000-0000-4000-8000-000000000019',true,jsonb_build_array(jsonb_build_object('reservation_id',public.get_ticket_inventory_parts('50000000-0000-4000-8000-000000000019')#>>'{items,0,reservations,0,reservation_id}','used_quantity',1)))->>'success')::boolean,'own employee completes through real inventory RPC');
RESET ROLE;
SELECT test_auth.assert((SELECT physical_quantity=4 AND reserved_quantity=0 AND available_quantity=4 FROM public.inventory_balances WHERE item_id='73000000-0000-4000-8000-000000000019'),'inventory completion consumes one and releases one');
SELECT test_auth.assert((SELECT status='Teste Final' AND repair_start_at IS NULL AND repair_end_at IS NOT NULL AND repair_successful=true FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000019'),'inventory completion advances phase and sets result on server');
SELECT test_auth.assert((SELECT count(*)=1 AND bool_and(r.consumed_quantity=1 AND r.released_quantity=1 AND r.status='consumed' AND tp.status='consumed') FROM public.inventory_reservations r JOIN public.ticket_part_items tp ON tp.workspace_id=r.workspace_id AND tp.id=r.ticket_part_item_id WHERE tp.ticket_id='50000000-0000-4000-8000-000000000019'),'reservation and part states match server-derived usage');
SELECT test_auth.assert((SELECT count(*)=3 AND bool_and(actor_employee_id=(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee') AND actor_user_id IS NULL AND actor_name=(SELECT name FROM public.employees WHERE id=(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'))) AND sum(physical_delta)=-1 AND sum(reserved_delta)=0 FROM public.inventory_movements WHERE ticket_id='50000000-0000-4000-8000-000000000019'),'stock ledger records reserve, consume, release and authenticated operational employee');
ROLLBACK TO SAVEPOINT inventory_real_completion;
RELEASE SAVEPOINT inventory_real_completion;
INSERT INTO audit_multirole_result VALUES('own technician legitimate inventory completion preserves stock and server metadata',jsonb_build_object('allowed',true,'rows',1,'pass',true,'expected','1','inventory_balances_validated',true,'server_actor_validated',true));
RESET ROLE;
SELECT test,result FROM audit_multirole_result ORDER BY test;
ROLLBACK;
