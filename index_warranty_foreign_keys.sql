-- Cover the self-referencing warranty foreign keys for predictable performance
-- when PostgreSQL validates updates or deletes on referenced tickets.

create index if not exists idx_tickets_warranty_origin_id
    on public.tickets (warranty_origin_ticket_id);

create index if not exists idx_tickets_warranty_converted_id
    on public.tickets (warranty_converted_ticket_id);
