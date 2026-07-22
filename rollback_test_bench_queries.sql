begin;

drop function if exists public.get_test_bench_page(integer, jsonb, boolean, boolean);
drop index if exists public.idx_tickets_test_bench_queue;

commit;
