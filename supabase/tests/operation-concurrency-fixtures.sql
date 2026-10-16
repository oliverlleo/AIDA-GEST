-- Included only by local synthetic operation tests. Deterministic IDs are unrelated to real data.
DO $$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR inet_server_port()<>54329
    OR current_database() NOT LIKE 'aida_auth_review_%' THEN RAISE EXCEPTION 'Named loopback synthetic database required';END IF;
END $$;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','94cb3619-0000-4000-8000-000000000002');
SELECT set_config('request.method','',false);
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('94cb3619-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002',clock_timestamp()) ON CONFLICT DO NOTHING;
UPDATE public.workspaces SET tracker_config=coalesce(tracker_config,'{}'::jsonb)||'{"customization":{"modules":true,"workflow":true},"modules":{"inventory":true,"agenda":true},"workflow":{"parts_control":true}}'::jsonb WHERE id='20000000-0000-4000-8000-000000000002';
INSERT INTO public.inventory_items(id,workspace_id,name,sku) VALUES('94cb3619-0000-4000-8000-000000000010','20000000-0000-4000-8000-000000000002','OPERATION CAS synthetic item','OPERATION-CAS-ITEM') ON CONFLICT DO NOTHING;
INSERT INTO public.inventory_locations(id,workspace_id,name,normalized_address) VALUES('94cb3619-0000-4000-8000-000000000011','20000000-0000-4000-8000-000000000002','OPERATION CAS synthetic location','operation-cas-location') ON CONFLICT DO NOTHING;
INSERT INTO public.inventory_purchases(id,workspace_id,supplier_name_snapshot,status,created_by_user_id,created_by_name)
VALUES('94cb3619-0000-4000-8000-000000000012','20000000-0000-4000-8000-000000000002','Synthetic supplier','ordered','10000000-0000-4000-8000-000000000002','Synthetic owner') ON CONFLICT DO NOTHING;
INSERT INTO public.inventory_purchase_items(id,workspace_id,purchase_id,item_id,item_name_snapshot,ordered_quantity,unit_cost)
VALUES('94cb3619-0000-4000-8000-000000000013','20000000-0000-4000-8000-000000000002','94cb3619-0000-4000-8000-000000000012','94cb3619-0000-4000-8000-000000000010','OPERATION CAS synthetic item',10,2) ON CONFLICT DO NOTHING;
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,status,technician_id,analysis_deadline,deadline)
VALUES('94cb3619-0000-4000-8000-000000000020','20000000-0000-4000-8000-000000000002','Synthetic operation schedule','OPERATION-CAS-SCHEDULE','Synthetic device','Synthetic defect','Analise Tecnica',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),now()+interval '32 days',now()+interval '33 days') ON CONFLICT DO NOTHING;
INSERT INTO public.ticket_appointments(id,workspace_id,ticket_id,technician_id,appointment_type,scheduled_start,scheduled_end,created_by_user_id)
SELECT '94cb3619-0000-4000-8000-000000000021','20000000-0000-4000-8000-000000000002','94cb3619-0000-4000-8000-000000000020',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),'analysis',(current_date+30+time '10:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+30+time '10:30') AT TIME ZONE 'America/Sao_Paulo','10000000-0000-4000-8000-000000000002'
WHERE NOT EXISTS(SELECT 1 FROM public.ticket_appointments WHERE id='94cb3619-0000-4000-8000-000000000021');
