-- Real DB regressions for scheduling (including XOR creator identity) and inventory RPCs.
DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet AND inet_server_addr() IS DISTINCT FROM '::1'::inet THEN RAISE EXCEPTION 'Local SQL tests require loopback PostgreSQL'; END IF; END $$;
SET ROLE authenticated;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO test_auth.fixture SELECT 'rejoined_employee',id FROM public.list_workspace_staff('20000000-0000-4000-8000-000000000002') WHERE email='fixture3@example.invalid' AND access_status='active';
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,technician_id,status)
VALUES('50000000-0000-4000-8000-000000000005','20000000-0000-4000-8000-000000000002','Synthetic scheduled client','REVIEW_SCHEDULE','Synthetic device','Synthetic defect',now()+interval '2 days',now()+interval '3 days',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'Analise Tecnica');
SELECT public.update_workspace_tracker_config('{"customization":{"modules":true,"workflow":true},"modules":{"inventory":true},"workflow":{"parts_control":true}}');
INSERT INTO test_auth.fixture SELECT 'inventory_item',public.save_inventory_item('{"name":"Synthetic inventory item","sku":"AUTH-REVIEW-SKU","track_stock":false}');
SELECT test_auth.assert((public.get_inventory_dashboard()->>'active_items')::integer=1,'owner can use existing inventory backend via Auth');
SELECT test_auth.expect_error('SELECT * FROM public.inventory_items','42501');
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002');
SELECT public.create_ticket_appointment('50000000-0000-4000-8000-000000000005',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'analysis',
    (current_date+1+time '10:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+1+time '10:30') AT TIME ZONE 'America/Sao_Paulo','Synthetic appointment');
SELECT test_auth.assert((SELECT created_by_user_id IS NULL AND created_by_employee_id=(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee') FROM public.ticket_appointments WHERE ticket_id='50000000-0000-4000-8000-000000000005'),'authenticated employee schedules with historical employee ID and XOR creator');
SELECT public.get_ticket_appointments('50000000-0000-4000-8000-000000000005');
SELECT public.get_inventory_catalog_page('50000000-0000-4000-8000-000000000005');
SELECT public.get_ticket_inventory_parts('50000000-0000-4000-8000-000000000005');
SELECT test_auth.expect_error('SELECT public.save_inventory_item(''{"name":"Forbidden technician item"}'')');
SELECT test_auth.expect_error('SELECT public.get_inventory_dashboard()');
SELECT test_auth.expect_error('SELECT public.create_ticket_appointment(''50000000-0000-4000-8000-000000000004'',''30000000-0000-4000-8000-000000000001'',''analysis'',now()+interval ''1 day'',now()+interval ''1 day 30 minutes'')');
SELECT test_auth.login(4,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.assert((public.get_inventory_dashboard()->>'active_items')::integer=1,'attendant inventory management preserved');
SELECT test_auth.expect_error('SELECT public.save_inventory_item(''{"name":"Forbidden attendant item"}'')');
SELECT test_auth.login(5,'20000000-0000-4000-8000-000000000002');
SELECT test_auth.expect_error('SELECT public.get_inventory_dashboard()');
SELECT test_auth.expect_error('SELECT public.get_ticket_inventory_parts(''50000000-0000-4000-8000-000000000005'')');
RESET ROLE;
SELECT 'PASS: schedule creator XOR, technician agenda and inventory RPC role/tenant authorization' AS result;
