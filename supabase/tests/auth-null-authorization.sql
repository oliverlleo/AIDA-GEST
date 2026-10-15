-- NULL assignment is never proof of an employee's authority. Synthetic local
-- fixtures, fresh sessions, and every successful control roll back together.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Loopback PostgreSQL required'; END IF; END $$;
INSERT INTO auth.sessions(id,user_id,created_at)
SELECT ('99500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
       ('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,clock_timestamp()
FROM generate_series(2,3)n;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000002');
UPDATE public.workspaces SET tracker_config=coalesce(tracker_config,'{}'::jsonb)
 || '{"customization":{"modules":true,"workflow":true,"ticket_fields":true},"modules":{"inventory":true,"customers":true,"agenda":true},"workflow":{"parts_control":true,"analysis_timer":true,"repair_timer":true,"final_test":true,"warranty_control":true},"ticket_field_modes":{"analysis_schedule":"optional","repair_schedule":"optional","responsible":"optional"}}'::jsonb
WHERE id='20000000-0000-4000-8000-000000000002';
INSERT INTO public.customers(id,workspace_id,name,person_type)
VALUES('99500000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000002','Synthetic NULL authorization customer','person');
INSERT INTO public.inventory_locations(id,workspace_id,name,normalized_address)
VALUES('99500000-0000-4000-8000-000000000401','20000000-0000-4000-8000-000000000002','Synthetic NULL location','synthetic_null_authorization');
INSERT INTO public.inventory_items(id,workspace_id,name,sku,track_stock,default_location_id)
VALUES('99500000-0000-4000-8000-000000000301','20000000-0000-4000-8000-000000000002','Synthetic NULL part','NULL-AUTHORIZATION',true,'99500000-0000-4000-8000-000000000401');
INSERT INTO public.inventory_balances(workspace_id,item_id,location_id,physical_quantity,reserved_quantity)
VALUES('20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000301','99500000-0000-4000-8000-000000000401',9,0);
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,status,budget_status,repair_start_at)
VALUES('99500000-0000-4000-8000-000000000201','20000000-0000-4000-8000-000000000002','Synthetic NULL repair','NULL_AUTH_REPAIR','Synthetic device','Synthetic defect',now()+interval '2 days',now()+interval '3 days','Andamento Reparo','Aprovado',now()),
      ('99500000-0000-4000-8000-000000000202','20000000-0000-4000-8000-000000000002','Synthetic NULL analysis','NULL_AUTH_ANALYSIS','Synthetic device','Synthetic defect',now()+interval '2 days',now()+interval '3 days','Analise Tecnica','Pendente',NULL),
      ('99500000-0000-4000-8000-000000000203','20000000-0000-4000-8000-000000000002','Synthetic NULL approval','NULL_AUTH_APPROVAL','Synthetic device','Synthetic defect',now()+interval '2 days',now()+interval '3 days','Aprovacao','Pendente',NULL);
INSERT INTO public.tickets(id,workspace_id,customer_id,client_name,os_number,device_model,defect_reported,status,deadline,analysis_deadline,repair_successful,delivered_at)
VALUES('99500000-0000-4000-8000-000000000204','20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000101','Synthetic warranty origin','NULL_AUTH_ORIGIN','Synthetic device','Synthetic defect','Finalizado',now()-interval '1 day',now()-interval '2 days',true,now()-interval '1 day');
INSERT INTO public.tickets(id,workspace_id,customer_id,client_name,os_number,device_model,defect_reported,status,deadline,analysis_deadline,warranty_claim,warranty_origin_ticket_id)
VALUES('99500000-0000-4000-8000-000000000205','20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000101','Synthetic NULL warranty','NULL_AUTH_CLAIM','Synthetic device','Synthetic defect','Analise Tecnica',now()+interval '3 days',now()+interval '2 days',true,'99500000-0000-4000-8000-000000000204');
INSERT INTO public.ticket_part_items(id,workspace_id,ticket_id,requested_item_id,requested_name_snapshot,requested_quantity,request_stage,status,requested_by_user_id,requested_by_name)
VALUES('99500000-0000-4000-8000-000000000701','20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000201','99500000-0000-4000-8000-000000000301','Synthetic consumed part',1,'repair','consumed','10000000-0000-4000-8000-000000000002','Synthetic owner');
INSERT INTO public.inventory_reservations(id,workspace_id,ticket_part_item_id,item_id,location_id,reserved_quantity,consumed_quantity,status)
VALUES('99500000-0000-4000-8000-000000000801','20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000701','99500000-0000-4000-8000-000000000301','99500000-0000-4000-8000-000000000401',1,1,'consumed');
INSERT INTO public.ticket_appointments(id,workspace_id,ticket_id,technician_id,appointment_type,scheduled_start,scheduled_end,status,created_by_user_id)
SELECT '99500000-0000-4000-8000-000000000901','20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000203',id,'analysis',
       (current_date+10+time '09:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+10+time '09:30') AT TIME ZONE 'America/Sao_Paulo','scheduled','10000000-0000-4000-8000-000000000002'
FROM test_auth.fixture WHERE name='rejoined_employee';

SET LOCAL ROLE authenticated;
SELECT test_auth.assert(jsonb_array_length(public.get_ticket_appointments('99500000-0000-4000-8000-000000000203'))=1,'owner has real nonempty appointment control');
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000003');
SELECT test_auth.assert((SELECT is_technician AND NOT is_admin AND NOT is_attendant FROM public.get_current_actor_context()),'current technical role is active');
SELECT test_auth.assert(NOT EXISTS(SELECT 1 FROM public.tickets WHERE id='99500000-0000-4000-8000-000000000203'),'unassigned approval is hidden by RLS');
-- Check the actual authorization message, so an unrelated input/domain error
-- cannot be counted as successful authorization coverage.
DO $test$
DECLARE c record; m text; s text;
BEGIN
 FOR c IN SELECT * FROM (VALUES
  ('repair unassigned',$q$SELECT public.complete_repair_with_inventory('99500000-0000-4000-8000-000000000201',true,'[]')$q$,'Somente o tecnico responsavel'),
  ('warranty unassigned',$q$SELECT public.complete_warranty_analysis('99500000-0000-4000-8000-000000000205',true,'Synthetic valid technical warranty report')$q$,'Somente o tecnico responsavel'),
  ('warranty inventory unassigned',$q$SELECT public.complete_warranty_analysis_with_inventory('99500000-0000-4000-8000-000000000205','Synthetic valid technical warranty report')$q$,'Somente o tecnico responsavel'),
  ('request parts unassigned',$q$SELECT public.request_ticket_inventory_parts('99500000-0000-4000-8000-000000000202','[{"item_id":"99500000-0000-4000-8000-000000000301","quantity":1}]','analysis',false)$q$,'Somente o tecnico responsavel'),
  ('return consumed part unassigned',$q$SELECT public.return_ticket_inventory('99500000-0000-4000-8000-000000000801',1,'Synthetic valid return reason')$q$,'Somente o tecnico responsavel'),
  ('read appointments unassigned approval',$q$SELECT public.get_ticket_appointments('99500000-0000-4000-8000-000000000203')$q$,'Acesso negado'),
  ('create appointment unassigned approval',$q$SELECT public.create_ticket_appointment('99500000-0000-4000-8000-000000000203',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'analysis',(current_date+11+time '09:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+11+time '09:30') AT TIME ZONE 'America/Sao_Paulo')$q$,'Acesso negado')
 )v(label,query,guard_message) LOOP
  BEGIN EXECUTE c.query; RAISE EXCEPTION USING ERRCODE='ZX999',MESSAGE='Unexpected authorization success: '||c.label;
  EXCEPTION WHEN SQLSTATE 'ZX999' THEN RAISE;
  WHEN OTHERS THEN GET STACKED DIAGNOSTICS m=MESSAGE_TEXT,s=RETURNED_SQLSTATE;
    IF strpos(m,c.guard_message)=0 THEN RAISE EXCEPTION 'Wrong rejection for %: % / %',c.label,s,m; END IF;
    RAISE NOTICE 'PASS NULL authorization: % / % / %',c.label,s,m;
  END;
 END LOOP;
END
$test$;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000002');
SELECT test_auth.expect_error($q$SELECT public.request_ticket_inventory_parts('99500000-0000-4000-8000-000000000202','[{"item_id":"99500000-0000-4000-8000-000000000301","quantity":1}]',NULL,false)$q$,'22023');
SELECT test_auth.expect_error($q$SELECT public.request_ticket_inventory_parts('99500000-0000-4000-8000-000000000202','[{"item_id":"99500000-0000-4000-8000-000000000301","quantity":1}]','analysis',NULL)$q$,'22023');
SELECT public.update_employee_access((SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Synthetic technical attendant',ARRAY['tecnico','atendente']);
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000003');
SELECT test_auth.assert((SELECT is_technician AND is_attendant AND NOT is_admin FROM public.get_current_actor_context()),'combined role context is valid');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.tickets WHERE id='99500000-0000-4000-8000-000000000205'),'attendant role genuinely exposes target row');
DO $$ DECLARE m text; BEGIN
 BEGIN
  UPDATE public.tickets SET warranty_status='covered',warranty_technical_report='Synthetic valid technical warranty report',warranty_needs_parts=false
  WHERE id='99500000-0000-4000-8000-000000000205';
  RAISE EXCEPTION USING ERRCODE='ZX999',MESSAGE='Combined role bypassed private warranty assignment guard';
 EXCEPTION WHEN SQLSTATE 'ZX999' THEN RAISE;
 WHEN OTHERS THEN GET STACKED DIAGNOSTICS m=MESSAGE_TEXT;
  IF strpos(m,'Somente o tecnico responsavel')=0 THEN RAISE EXCEPTION 'Wrong private-trigger rejection: %',m; END IF;
  RAISE NOTICE 'PASS private warranty trigger: combined role + NULL assignment denied / %',m;
 END;
END $$;
-- Preserve the paired legitimate route with the exact same employee/session.
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000002');
UPDATE public.tickets SET technician_id=(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee') WHERE id='99500000-0000-4000-8000-000000000205';
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000003');
DO $$ DECLARE m text; BEGIN
 BEGIN
  UPDATE public.tickets SET warranty_status=NULL,warranty_technical_report='Synthetic valid technical warranty report',warranty_needs_parts=false
  WHERE id='99500000-0000-4000-8000-000000000205';
  RAISE EXCEPTION USING ERRCODE='ZX999',MESSAGE='NULL warranty decision accepted';
 EXCEPTION WHEN SQLSTATE 'ZX999' THEN RAISE;
 WHEN OTHERS THEN GET STACKED DIAGNOSTICS m=MESSAGE_TEXT;
  IF strpos(m,'Decisao de garantia invalida')=0 THEN RAISE EXCEPTION 'Wrong NULL-decision rejection: %',m; END IF;
  RAISE NOTICE 'PASS private warranty trigger: NULL decision denied / %',m;
 END;
END $$;
UPDATE public.tickets SET warranty_status='covered',warranty_technical_report='Synthetic valid technical warranty report',warranty_needs_parts=false
WHERE id='99500000-0000-4000-8000-000000000205';
SELECT test_auth.assert((SELECT warranty_status='covered' AND warranty_decided_by=(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee') FROM public.tickets WHERE id='99500000-0000-4000-8000-000000000205'),'assigned combined-role technician can make legitimate warranty decision');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000002');
UPDATE public.tickets SET technician_id=(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),deleted_at=now() WHERE id='99500000-0000-4000-8000-000000000201';
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000003');
SELECT test_auth.assert(NOT EXISTS(SELECT 1 FROM public.tickets WHERE id='99500000-0000-4000-8000-000000000201'),'deleted repair is hidden even from assigned technician-attendant');
SELECT test_auth.expect_error($q$SELECT public.return_ticket_inventory('99500000-0000-4000-8000-000000000801',1,'Synthetic valid return reason')$q$,'42501');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000002');
SAVEPOINT legitimate_recovery;
SELECT test_auth.assert((public.return_ticket_inventory('99500000-0000-4000-8000-000000000801',1,'Synthetic administrator recovery')->>'success')::boolean,'administrator can legitimately recover consumed part from recycle bin');
ROLLBACK TO SAVEPOINT legitimate_recovery;
RELEASE SAVEPOINT legitimate_recovery;
RESET ROLE;
SELECT test_auth.assert((SELECT returned_quantity=0 FROM public.inventory_reservations WHERE id='99500000-0000-4000-8000-000000000801'),'denied inventory return changed nothing');
SELECT test_auth.assert((SELECT count(*)=0 FROM public.ticket_part_items WHERE ticket_id='99500000-0000-4000-8000-000000000202'),'denied part request changed nothing');
ROLLBACK;
SELECT 'PASS: seven public NULL-assignment guards, NULL request parameters/decision, private warranty role union, deleted OS return, paired positive controls' AS result;
