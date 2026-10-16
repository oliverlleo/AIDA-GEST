-- Synthetic, loopback-only regressions for abuse protection. No production data.
-- Run after existing auth/operations fixtures and the abuse protection migration.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
    OR inet_server_port() <> 54329
    OR current_database() NOT LIKE 'aida_auth_review_%' THEN
  RAISE EXCEPTION 'Named loopback synthetic database required';
 END IF;
END $$;

SELECT test_auth.assert((SELECT count(*)=9 AND bool_and(pg_get_userbyid(p.proowner)='postgres')
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
 (n.nspname='private' AND p.proname IN('raise_request_limit','consume_request_budget','acquire_request_slots','check_request_budget','consume_team_budget','has_storage_upload_reservation','check_public_tracker_budget'))
 OR (n.nspname='public' AND p.proname IN('consume_edge_request_budget','reserve_storage_upload'))),'nine new helpers/RPCs have production-equivalent postgres ownership');
SELECT test_auth.assert((SELECT count(*)=3 AND bool_and(pg_get_userbyid(c.relowner)='postgres')
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='private' AND c.relname IN('abuse_settings','request_budgets','storage_upload_reservations')),'three new tables have production-equivalent postgres ownership');
SELECT test_auth.assert(NOT has_function_privilege('anon','private.check_public_tracker_budget(uuid)','EXECUTE')
 AND NOT has_function_privilege('authenticated','private.check_public_tracker_budget(uuid)','EXECUTE')
 AND NOT has_function_privilege('anon','private.consume_team_budget(uuid)','EXECUTE')
 AND NOT has_function_privilege('authenticated','private.consume_team_budget(uuid)','EXECUTE'),'private budget helpers remain unavailable to client roles');
SELECT test_auth.assert((SELECT file_size_limit=20971520 AND allowed_mime_types=ARRAY['image/*'] AND NOT public AND name=id
 FROM storage.buckets WHERE id='ticket_photos'),'server photo bucket limits allow camera image formats up to 20 MB');
SELECT test_auth.assert((SELECT file_size_limit=5242880 AND allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp','image/gif'] AND public AND name=id
 FROM storage.buckets WHERE id='workspace_logos'),'server logo bucket limits match its 5 MB image handler');
SELECT test_auth.assert((SELECT file_size_limit=5242880 AND allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp'] AND NOT public AND name=id
 FROM storage.buckets WHERE id='inventory_images'),'server inventory bucket existing limits and privacy preserved');

INSERT INTO auth.sessions(id,user_id,created_at)
SELECT ('99000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
       ('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,clock_timestamp()
FROM generate_series(1,8)n ON CONFLICT DO NOTHING;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000002');
UPDATE public.workspaces SET tracker_config=coalesce(tracker_config,'{}'::jsonb)
 || '{"customization":{"modules":true,"workflow":true,"overview":true},"modules":{"inventory":true,"public_tracker":true},"workflow":{"parts_control":true}}'::jsonb
WHERE id='20000000-0000-4000-8000-000000000002';

-- More real rows than every default page size, so NULL cannot pass by accident.
INSERT INTO public.tickets(id,workspace_id,client_name,os_number,device_model,defect_reported,status,priority_requested,analysis_deadline,deadline,technician_id,public_token)
SELECT ('99100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
       '20000000-0000-4000-8000-000000000002','ABUSE_SYNTHETIC_'||n,
       'ABUSE_SYNTHETIC_'||n,'Synthetic device','Synthetic defect','Aprovacao',true,
       now()+interval '1 day',now()+interval '2 days',(SELECT id FROM test_auth.fixture WHERE name='owner_employee'),
       ('99100000-0000-4000-8000-'||lpad((8000+n)::text,12,'0'))::uuid
FROM generate_series(1,205)n;
INSERT INTO public.inventory_items(id,workspace_id,name,sku,track_stock)
VALUES('99100000-0000-4000-8000-000000001001','20000000-0000-4000-8000-000000000002','Abuse synthetic item','ABUSE_SYNTHETIC',false);
INSERT INTO public.inventory_locations(id,workspace_id,name,normalized_address)
VALUES('99100000-0000-4000-8000-000000001002','20000000-0000-4000-8000-000000000002','Abuse synthetic location','abuse_synthetic_location');
INSERT INTO public.inventory_movements(id,workspace_id,item_id,location_id,movement_type,physical_delta,reserved_delta,actor_user_id,actor_name,reason)
SELECT ('99100000-0000-4000-8000-'||lpad((2000+n)::text,12,'0'))::uuid,
       '20000000-0000-4000-8000-000000000002','99100000-0000-4000-8000-000000001001',
       '99100000-0000-4000-8000-000000001002','opening',1,0,
       '10000000-0000-4000-8000-000000000002','Synthetic actor','Synthetic pagination fixture'
FROM generate_series(1,55)n;

SET LOCAL ROLE authenticated;
SELECT test_auth.assert(jsonb_array_length(public.get_operational_queue('all','auto',p_limit=>NULL)->'items')=200,'operational NULL limit defaults to 200 with 205+ visible rows');
SELECT test_auth.assert(jsonb_array_length(public.get_operational_queue('all','auto',p_limit=>5)->'items')=5,'operational requested smaller page preserved');
SELECT test_auth.assert(jsonb_array_length(public.get_overview_queue_page('priorityTickets',p_limit=>NULL)->'items')=20,'overview NULL limit defaults to 20 with 205 priority rows');
SELECT test_auth.assert(jsonb_array_length(public.get_overview_queue_page('priorityTickets',p_limit=>5)->'items')=5,'overview smaller page preserved');
SELECT test_auth.assert(jsonb_array_length(public.get_inventory_movements_page('99100000-0000-4000-8000-000000001001',NULL)->'items')=30,'inventory movement NULL limit defaults to 30 with 55 rows');
SELECT test_auth.assert(jsonb_array_length(public.get_inventory_movements_page('99100000-0000-4000-8000-000000001001',5)->'items')=5,'inventory movement smaller page preserved');
SELECT test_auth.expect_error($q$SELECT public.get_operational_queue('all','auto',p_limit=>201)$q$);
SELECT test_auth.expect_error($q$SELECT public.get_overview_queue_page('priorityTickets',p_limit=>51)$q$);
SELECT test_auth.expect_error($q$SELECT public.get_inventory_movements_page(p_limit=>51)$q$);
SELECT test_auth.expect_error($q$SELECT public.get_operational_queue('all','auto',p_limit=>-1)$q$);
SELECT test_auth.expect_error($q$SELECT public.get_overview_queue_page('priorityTickets',p_limit=>0)$q$);

SELECT test_auth.assert((public.set_inventory_item_locations('99100000-0000-4000-8000-000000001001',
 ARRAY['99100000-0000-4000-8000-000000001002','99100000-0000-4000-8000-000000001002']::uuid[],
 '99100000-0000-4000-8000-000000001002')->>'location_count')::integer=1,'duplicate locations counted once and real default location retained');
SELECT test_auth.expect_error($q$SELECT public.set_inventory_item_locations('99100000-0000-4000-8000-000000001001',
 array_fill('99100000-0000-4000-8000-000000001002'::uuid,ARRAY[257]))$q$);
RESET ROLE;
SELECT test_auth.assert((SELECT default_location_id='99100000-0000-4000-8000-000000001002' FROM public.inventory_items WHERE id='99100000-0000-4000-8000-000000001001'),'oversize rejected without changing default location');
SET LOCAL ROLE authenticated;

-- New public RPCs must retain identity, current membership and role enforcement.
SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000000001/owner-heic.heic',1024,'image/heic');
SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000002/abuse-owner-logo.png',1024,'image/png');
SELECT public.reserve_storage_upload('inventory_images','20000000-0000-4000-8000-000000000002/inventory/99100000-0000-4000-8000-000000001001/abuse.png',1024,'image/png');
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000000001/too-big.jpg',20971521,'image/jpeg')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000002/too-big.png',5242881,'image/png')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('inventory_images','20000000-0000-4000-8000-000000000002/inventory/99100000-0000-4000-8000-000000001001/too-big.png',5242881,'image/png')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000000001/script.html',100,'text/html')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('inventory_images','20000000-0000-4000-8000-000000000002/inventory/99100000-0000-4000-8000-000000001001/script.svg',100,'image/svg+xml')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000001/cross-company.png',100,'image/png')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/../cross.jpg',100,'image/jpeg')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('unknown','20000000-0000-4000-8000-000000000002/photo.jpg',100,'image/jpeg')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000002/empty.png',0,'image/png')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000002/null.png',NULL,'image/png')$q$);

SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000003');
SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/before-os.heic',1024,'image/heic');
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000002/tech-logo.png',1024,'image/png')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('inventory_images','20000000-0000-4000-8000-000000000002/inventory/99100000-0000-4000-8000-000000001001/tech.png',1024,'image/png')$q$);
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000000001/hidden-owner-ticket.jpg',1024,'image/jpeg')$q$);
SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000001');
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000002/owner-a-tech-in-b.png',1024,'image/png')$q$,'42501');
SELECT test_auth.login(1,'20000000-0000-4000-8000-000000000001','99000000-0000-4000-8000-000000000001');
SELECT public.reserve_storage_upload('workspace_logos','20000000-0000-4000-8000-000000000001/owner-a-logo.png',1024,'image/png');
SELECT test_auth.login(6,NULL,'99000000-0000-4000-8000-000000000006');
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/unaffiliated.jpg',1024,'image/jpeg')$q$);
SELECT test_auth.login(7,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000007');
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/unconfirmed.jpg',1024,'image/jpeg')$q$);
RESET ROLE;
UPDATE public.workspace_memberships SET status='blocked'
WHERE workspace_id='20000000-0000-4000-8000-000000000002' AND user_id='10000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000003');
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/before-os.heic',1024,'image/heic')$q$,'42501');
RESET ROLE;
UPDATE public.workspace_memberships SET status='active'
WHERE workspace_id='20000000-0000-4000-8000-000000000002' AND user_id='10000000-0000-4000-8000-000000000003';
SET LOCAL ROLE anon;
SELECT test_auth.expect_error($q$SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/anon.jpg',1024,'image/jpeg')$q$,'42501');
RESET ROLE;

-- A reservation is required only after the coordinated rollout flag is enabled.
UPDATE private.abuse_settings SET storage_reservation_required=true WHERE singleton;
SELECT test_auth.assert(NOT has_function_privilege('anon','public.reserve_storage_upload(text,text,bigint,text)','EXECUTE'),'anonymous upload reservation RPC is revoked');
SELECT test_auth.assert(NOT has_function_privilege('anon','public.consume_edge_request_budget(text,uuid)','EXECUTE'),'anonymous Edge budget RPC is revoked');
SET LOCAL ROLE authenticated;
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000003');
INSERT INTO storage.objects(bucket_id,name,metadata)
VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/before-os.heic','{"size":1024,"mimetype":"image/heic"}');
SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/owner-attempt.jpg',1024,'image/jpeg');
SELECT public.reserve_storage_upload('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/expired.jpg',1024,'image/jpeg');
SELECT test_auth.expect_error($q$INSERT INTO storage.objects(bucket_id,name,metadata)
 VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/unreserved.jpg','{"size":1024,"mimetype":"image/jpeg"}')$q$,'42501');
SELECT test_auth.expect_error('SELECT * FROM private.storage_upload_reservations','42501');
SELECT test_auth.expect_error('UPDATE private.abuse_settings SET storage_reservation_required=false','42501');
SELECT test_auth.expect_error('DELETE FROM private.request_budgets','42501');
SELECT test_auth.expect_error($q$SELECT private.consume_request_budget('write_burst','10000000-0000-4000-8000-000000000003',999999,1)$q$,'42501');
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000002');
SELECT test_auth.expect_error($q$INSERT INTO storage.objects(bucket_id,name,metadata)
 VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/owner-attempt.jpg','{"size":1024,"mimetype":"image/jpeg"}')$q$,'42501');
RESET ROLE;
UPDATE private.storage_upload_reservations SET expires_at=clock_timestamp()-interval '1 second'
WHERE path='20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/expired.jpg';
SET LOCAL ROLE authenticated;
SELECT test_auth.login(3,'20000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000003');
SELECT test_auth.expect_error($q$INSERT INTO storage.objects(bucket_id,name,metadata)
 VALUES('ticket_photos','20000000-0000-4000-8000-000000000002/99100000-0000-4000-8000-000000009999/expired.jpg','{"size":1024,"mimetype":"image/jpeg"}')$q$,'42501');
RESET ROLE;

-- Direct helper checks use their own tiny synthetic budget, never a large loop.
SELECT private.consume_request_budget('qa_synthetic','qa-synthetic',2,60);
SELECT private.consume_request_budget('qa_synthetic','qa-synthetic',2,60);
SELECT test_auth.expect_error($q$SELECT private.consume_request_budget('qa_synthetic','qa-synthetic',2,60)$q$,'PGRST');
SELECT test_auth.assert((SELECT used=2 FROM private.request_budgets WHERE scope='qa_synthetic' AND subject_hash=md5('qa-synthetic') AND window_seconds=60),'full budget rejected without overshooting');
UPDATE private.request_budgets SET window_started=window_started-1 WHERE scope='qa_synthetic';
SELECT private.consume_request_budget('qa_synthetic','qa-synthetic',2,60);
SELECT test_auth.assert((SELECT used=1 FROM private.request_budgets WHERE scope='qa_synthetic' AND subject_hash=md5('qa-synthetic') AND window_seconds=60),'expired window resets without blocking normal use');

-- Both legitimate public endpoints must still return the capability's ticket.
DELETE FROM private.request_budgets WHERE scope LIKE 'public_%';
SELECT set_config('request.method','POST',true);
SELECT set_config('aida.public_budget_checked','',true);
SET LOCAL ROLE anon;
SELECT test_auth.assert((SELECT count(*)=1 FROM public.get_client_ticket_details_public('99100000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000008001')),'legitimate public tracker still returns exactly its ticket');
RESET ROLE;
SELECT test_auth.assert((SELECT used=1 FROM private.request_budgets WHERE scope='public_minute' AND subject_hash=md5('all') AND window_seconds=60),'base public tracker consumes one unit');
DELETE FROM private.request_budgets WHERE scope LIKE 'public_%';
SELECT set_config('aida.public_budget_checked','',true);
SET LOCAL ROLE anon;
SELECT test_auth.assert((SELECT count(*)=1 FROM public.get_client_ticket_details_public_configurable('99100000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000008001')),'legitimate configurable tracker still returns exactly its ticket');
RESET ROLE;
SELECT test_auth.assert((SELECT used=1 FROM private.request_budgets WHERE scope='public_minute' AND subject_hash=md5('all') AND window_seconds=60),'configurable wrapper and base share one budget unit');

SELECT 'PASS: synthetic pagination bounds, deduplication, upload reservations and role isolation' AS result;
ROLLBACK;
