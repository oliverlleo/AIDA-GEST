\set ON_ERROR_STOP on
SET application_name='aida_operation_schedule_first';
BEGIN;
SELECT test_auth.login(2,'20000000-0000-4000-8000-000000000002','94cb3619-0000-4000-8000-000000000002');
SET LOCAL ROLE authenticated;
SELECT set_config('request.method','POST',true);
SELECT set_config('request.path','/rpc/reschedule_ticket_appointment',true);
SELECT set_config('request.headers','{"x-workspace-id":"20000000-0000-4000-8000-000000000002","x-aida-operation-version":"{\"resource\":\"ticket_appointments\",\"id\":\"94cb3619-0000-4000-8000-000000000021\",\"revision\":1}"}',true);
SELECT public.reschedule_ticket_appointment('94cb3619-0000-4000-8000-000000000021',(SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'),(current_date+30+time '11:00') AT TIME ZONE 'America/Sao_Paulo',(current_date+30+time '11:30') AT TIME ZONE 'America/Sao_Paulo','first concurrent reschedule');
SELECT 'LOCK_HELD';
SELECT pg_sleep(2);
COMMIT;
SELECT 'OPERATION_FIRST_SAVED';
