\set ON_ERROR_STOP on
\ir operation-concurrency-fixtures.sql
SELECT test_auth.assert((SELECT revision=1 AND status='ordered' FROM public.inventory_purchases WHERE id='94cb3619-0000-4000-8000-000000000012'),'fresh purchase for actual two-session partial receipt race');
