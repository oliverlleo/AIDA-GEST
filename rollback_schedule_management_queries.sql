begin;

drop function if exists public.get_unscheduled_ticket_page(
    text, uuid, text, text, date, boolean, integer, jsonb, boolean
);
drop index if exists public.idx_tickets_schedule_queue;

commit;
