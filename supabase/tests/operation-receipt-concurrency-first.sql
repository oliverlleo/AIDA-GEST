\set ON_ERROR_STOP on
SET application_name='aida_operation_receipt_first';
BEGIN;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','94cb3619-0000-4000-8000-000000000002');
SET LOCAL ROLE authenticated;
SELECT set_config('request.method','POST',true);
SELECT set_config('request.path','/rpc/receive_inventory_purchase',true);
SELECT set_config('request.headers','{"x-workspace-id":"20000000-0000-4000-8000-000000000002","x-aida-operation-version":"{\"resource\":\"inventory_purchases\",\"id\":\"94cb3619-0000-4000-8000-000000000012\",\"revision\":1}"}',true);
SELECT public.receive_inventory_purchase('94cb3619-0000-4000-8000-000000000012','[{"purchase_item_id":"94cb3619-0000-4000-8000-000000000013","quantity":2,"unit_cost":2,"destination":"stock","location_id":"94cb3619-0000-4000-8000-000000000011"}]',false);
SELECT 'LOCK_HELD';
SELECT pg_sleep(2);
COMMIT;
SELECT 'OPERATION_FIRST_SAVED';
