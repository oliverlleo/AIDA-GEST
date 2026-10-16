\set ON_ERROR_STOP on
\ir operation-concurrency-fixtures.sql
SELECT test_auth.assert((SELECT revision=1 FROM public.ticket_appointments WHERE id='94cb3619-0000-4000-8000-000000000021'),'fresh appointment for actual two-session reschedule race');
