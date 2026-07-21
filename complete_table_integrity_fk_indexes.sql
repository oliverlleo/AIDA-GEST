-- Completes the two composite child indexes reported after the integrity FKs
-- were installed. These prevent scans when validating or deleting parent rows.

begin;

create index if not exists internal_notes_workspace_ticket_idx
    on public.internal_notes (workspace_id, ticket_id);

create index if not exists tickets_workspace_outsourced_company_idx
    on public.tickets (workspace_id, outsourced_company_id);

commit;
