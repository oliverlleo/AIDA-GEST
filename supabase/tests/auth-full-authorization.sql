-- Post-correction regressions. Run on synthetic local fixtures after operations.
-- All fixtures and every successful probe are rolled back. No production data.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Loopback required'; END IF; END $$;
CREATE TEMP TABLE audit_regression_result(test text, result jsonb);
GRANT SELECT,INSERT ON audit_regression_result TO authenticated,anon;
CREATE FUNCTION pg_temp.expect_probe(p_test text,p_sql text,p_expected text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_rows bigint := 0; v_state text; v_result jsonb;
BEGIN
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    v_result:=jsonb_build_object('allowed',true,'rows',v_rows);
    RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='probe subtransaction rollback';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    v_result:=jsonb_build_object('allowed',false,'sqlstate',v_state);
  END;
  IF p_expected='denied' THEN
    IF COALESCE((v_result->>'allowed')::boolean,false) AND COALESCE((v_result->>'rows')::bigint,0)>0 THEN
      RAISE EXCEPTION 'Unauthorized success: % / %',p_test,v_result;
    END IF;
  ELSIF v_result IS DISTINCT FROM jsonb_build_object('allowed',true,'rows',p_expected::bigint) THEN
    RAISE EXCEPTION 'Legitimate action failed: % / %',p_test,v_result;
  END IF;
  INSERT INTO audit_regression_result VALUES(p_test,v_result||jsonb_build_object('expected',p_expected,'pass',true));
END $$;
SET ROLE authenticated;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status)
VALUES('50000000-0000-4000-8000-000000000006','20000000-0000-4000-8000-000000000002','Synthetic security client','FULL_AUDIT_6','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Aprovacao');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,analysis_started_at)
VALUES('50000000-0000-4000-8000-000000000007','20000000-0000-4000-8000-000000000002','Synthetic analysis client','FULL_AUDIT_7','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Analise Tecnica',now());
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status,budget_status,repair_start_at)
VALUES('50000000-0000-4000-8000-000000000008','20000000-0000-4000-8000-000000000002','Synthetic repair client','FULL_AUDIT_8','Synthetic device','Synthetic defect',now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Andamento Reparo','Aprovado',now());
RESET ROLE;
INSERT INTO public.notifications(id,ticket_id,recipient_role,type,message)
VALUES('60000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000006','admin','audit_fixture','ADMIN_ONLY_SYNTHETIC_SECRET'),
      ('60000000-0000-4000-8000-000000000003','50000000-0000-4000-8000-000000000006','tecnico','audit_fixture','TECHNICIAN_SYNTHETIC_NOTICE');
INSERT INTO public.notifications(id,ticket_id,recipient_user_id,type,message)
VALUES('60000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000002','audit_fixture','OWNER_ONLY_SYNTHETIC_SECRET'),
      ('60000000-0000-4000-8000-000000000004','50000000-0000-4000-8000-000000000006',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'audit_fixture','EMPLOYEE_ONLY_SYNTHETIC_NOTICE'),
      ('60000000-0000-4000-8000-000000000005','50000000-0000-4000-8000-000000000006',(SELECT id FROM test_auth.fixture WHERE name='owner_employee'),'audit_fixture','OTHER_EMPLOYEE_SYNTHETIC_SECRET');
INSERT INTO storage.objects(bucket_id,name)
VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000006/audit-assigned.jpg'),
      ('ticket_photos','20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000002/audit-hidden.jpg');
SET ROLE authenticated;
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.expect_probe('tech admin notification hidden',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000001'$$,'denied');
SELECT pg_temp.expect_probe('tech owner notification hidden',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000002'$$,'denied');
SELECT pg_temp.expect_probe('tech other employee notification hidden',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000005'$$,'denied');
SELECT pg_temp.expect_probe('tech role notification readable',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000003'$$,'1');
SELECT pg_temp.expect_probe('tech own notification readable',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000004'$$,'1');
SELECT pg_temp.expect_probe('tech own notification read acknowledgement',$$UPDATE public.notifications SET is_read=true WHERE id='60000000-0000-4000-8000-000000000004'$$,'1');
SELECT pg_temp.expect_probe('tech notification body immutable',$$UPDATE public.notifications SET message='FORGED_NOTICE' WHERE id='60000000-0000-4000-8000-000000000004'$$,'denied');
SELECT pg_temp.expect_probe('tech notification destination immutable',$$UPDATE public.notifications SET recipient_role='admin' WHERE id='60000000-0000-4000-8000-000000000004'$$,'denied');
SELECT pg_temp.expect_probe('tech notification insertion denied',$$INSERT INTO public.notifications(ticket_id,recipient_role,type,message) VALUES('50000000-0000-4000-8000-000000000006','admin','security_alert','FORGED_NOTICE')$$,'denied');
SELECT pg_temp.expect_probe('tech notification deletion denied',$$DELETE FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000004'$$,'denied');
SELECT pg_temp.expect_probe('tech budget send denied',$$UPDATE public.tickets SET budget_status='Enviado',budget_sent_at=now() WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech budget approval denied',$$UPDATE public.tickets SET budget_status='Aprovado' WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech budget value denied',$$UPDATE public.tickets SET budget_value=0.01 WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech approval bypass through status-only repair denied',$$UPDATE public.tickets SET status='Andamento Reparo' WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech approval bypass through status-only purchase denied',$$UPDATE public.tickets SET status='Compra Peca',parts_needed='Synthetic new part' WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech purchase fields denied',$$UPDATE public.tickets SET parts_status='Comprado',parts_purchased_at=now(),supplier_purchases='[{"synthetic":true}]'::jsonb WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech client field alteration denied',$$UPDATE public.tickets SET client_name='FORGED_CUSTOMER' WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech OS soft-delete denied',$$UPDATE public.tickets SET deleted_at=now() WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('tech legitimate notes update',$$UPDATE public.tickets SET tech_notes='Synthetic diagnosis' WHERE id='50000000-0000-4000-8000-000000000006'$$,'1');
SELECT pg_temp.expect_probe('tech legitimate analysis conclusion',$$UPDATE public.tickets SET status='Aprovacao',previous_status='Analise Tecnica',tech_notes='Synthetic completed diagnosis',parts_needed=NULL,parts_status='N/A' WHERE id='50000000-0000-4000-8000-000000000007'$$,'1');
SELECT pg_temp.expect_probe('tech legitimate repair completion RPC',$$SELECT public.complete_repair_with_timer('50000000-0000-4000-8000-000000000008',true)$$,'1');
SELECT pg_temp.expect_probe('tech legitimate deadline update',$$UPDATE public.tickets SET deadline=now()+interval '4 days',analysis_deadline=now()+interval '2 days' WHERE id='50000000-0000-4000-8000-000000000006'$$,'1');
SELECT pg_temp.expect_probe('tech legitimate checklist update',$$UPDATE public.tickets SET checklist_data='[{"item":"Synthetic checklist","ok":true}]'::jsonb,checklist_final_data='[{"item":"Synthetic final","ok":true}]'::jsonb WHERE id='50000000-0000-4000-8000-000000000006'$$,'1');
SELECT pg_temp.expect_probe('tech legitimate photo link update',$$UPDATE public.tickets SET photos_urls=ARRAY['20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000006/audit-assigned.jpg'] WHERE id='50000000-0000-4000-8000-000000000006'$$,'1');
SELECT pg_temp.expect_probe('tech hidden OS photo insertion denied',$$INSERT INTO storage.objects(bucket_id,name) VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000002/full-audit.jpg')$$,'denied');
SELECT pg_temp.expect_probe('tech hidden OS photo read denied',$$SELECT id FROM storage.objects WHERE name='20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000002/audit-hidden.jpg'$$,'denied');
SELECT pg_temp.expect_probe('tech hidden OS photo replacement denied',$$UPDATE storage.objects SET metadata='{}'::jsonb WHERE name='20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000002/audit-hidden.jpg'$$,'denied');
SELECT pg_temp.expect_probe('tech assigned OS photo insertion',$$INSERT INTO storage.objects(bucket_id,name) VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000006/full-audit.jpg')$$,'1');
SELECT pg_temp.expect_probe('tech assigned OS photo read',$$SELECT id FROM storage.objects WHERE name='20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000006/audit-assigned.jpg'$$,'1');
SELECT pg_temp.expect_probe('tech assigned OS photo replacement',$$UPDATE storage.objects SET metadata='{}'::jsonb WHERE name='20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000006/audit-assigned.jpg'$$,'1');
SELECT pg_temp.expect_probe('tech before-creation photo upload preserved',$$INSERT INTO storage.objects(bucket_id,name) VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000999/full-audit.jpg')$$,'1');
SELECT pg_temp.expect_probe('tech foreign company photo denied',$$INSERT INTO storage.objects(bucket_id,name) VALUES('ticket_photos','20000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000004/full-audit.jpg')$$,'denied');
SELECT test_auth.login(4,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.expect_probe('attendant OS soft-delete denied',$$UPDATE public.tickets SET deleted_at=now() WHERE id='50000000-0000-4000-8000-000000000006'$$,'denied');
SELECT pg_temp.expect_probe('attendant technical analysis start clock denied',$$UPDATE public.tickets SET analysis_started_at=now()+interval '1 second' WHERE id='50000000-0000-4000-8000-000000000007'$$,'denied');
SELECT pg_temp.expect_probe('attendant technical analysis completion denied',$$UPDATE public.tickets SET status='Aprovacao',previous_status='Analise Tecnica' WHERE id='50000000-0000-4000-8000-000000000007'$$,'denied');
SELECT pg_temp.expect_probe('attendant technical repair start clock denied',$$UPDATE public.tickets SET repair_start_at=now()+interval '1 second' WHERE id='50000000-0000-4000-8000-000000000008'$$,'denied');
SELECT pg_temp.expect_probe('attendant technical repair completion denied',$$UPDATE public.tickets SET status='Teste Final',previous_status='Andamento Reparo',repair_successful=true,repair_end_at=now() WHERE id='50000000-0000-4000-8000-000000000008'$$,'denied');
SELECT pg_temp.expect_probe('attendant legitimate budget send',$$UPDATE public.tickets SET budget_status='Enviado',budget_sent_at=now() WHERE id='50000000-0000-4000-8000-000000000006'$$,'1');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.expect_probe('owner legitimate soft-delete',$$UPDATE public.tickets SET deleted_at=now() WHERE id='50000000-0000-4000-8000-000000000006'$$,'1');
SELECT pg_temp.expect_probe('owner legitimate admin notification readable',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000001'$$,'1');
SELECT pg_temp.expect_probe('owner legitimate owner notification readable',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000002'$$,'1');
UPDATE public.tickets SET deleted_at=now() WHERE id='50000000-0000-4000-8000-000000000006';
SELECT pg_temp.expect_probe('owner recycle OS still readable',$$SELECT id FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000006' AND deleted_at IS NOT NULL$$,'1');
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.expect_probe('tech administrator-only recycle OS hidden',$$SELECT id FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000006' AND deleted_at IS NOT NULL$$,'denied');
SELECT pg_temp.expect_probe('tech recycle OS photo hidden',$$SELECT id FROM storage.objects WHERE name='20000000-0000-4000-8000-000000000002/50000000-0000-4000-8000-000000000006/audit-assigned.jpg'$$,'denied');
SELECT pg_temp.expect_probe('tech recycle OS notification hidden',$$SELECT id FROM public.notifications WHERE id='60000000-0000-4000-8000-000000000004'$$,'denied');
SELECT test_auth.login(4,'20000000-0000-4000-8000-000000000002');
SELECT pg_temp.expect_probe('attendant administrator-only recycle OS hidden',$$SELECT id FROM public.tickets WHERE id='50000000-0000-4000-8000-000000000006' AND deleted_at IS NOT NULL$$,'denied');
RESET ROLE;
SELECT test,result FROM audit_regression_result ORDER BY test;
ROLLBACK;
