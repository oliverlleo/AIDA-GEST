-- Emergency rollback for optimize_ticket_card_queries.sql.
begin;

drop function if exists public.get_ticket_cards_page(
    text, text, uuid, text, integer, jsonb,
    boolean, boolean, boolean, boolean, boolean
);

commit;
