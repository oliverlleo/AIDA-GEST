begin;

drop function if exists public.get_operational_ticket_page(
    text, text, text, uuid, text, integer, jsonb, boolean
);

commit;
