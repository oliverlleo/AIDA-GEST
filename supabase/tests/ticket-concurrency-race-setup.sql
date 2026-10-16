DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'Loopback test only';END IF;END $$;
SET ROLE authenticated;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002');
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,analysis_deadline,deadline,status,technician_id)
VALUES('6f000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','Race fixture','REVISION_LOCAL_RACE','Test device','Test defect',now()+interval '2 days',now()+interval '3 days','Aberto',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'));
