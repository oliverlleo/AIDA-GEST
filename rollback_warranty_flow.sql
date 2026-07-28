begin;

drop function if exists public.link_warranty_paid_ticket(uuid, uuid);
drop function if exists public.complete_warranty_analysis(uuid, boolean, text, boolean, text, text);
drop function if exists public.get_warranty_ticket_summaries(uuid[]);
drop function if exists public.get_warranty_eligible_tickets(uuid, text, integer);

drop trigger if exists aida_enforce_ticket_warranty on public.tickets;
drop function if exists private.enforce_ticket_warranty();
drop trigger if exists aida_adopt_legacy_warranty_customer on public.tickets;
drop function if exists private.adopt_legacy_warranty_customer();
drop trigger if exists aida_validate_warranty_tracker_config on public.workspaces;
drop function if exists private.validate_warranty_tracker_config();
drop function if exists public.aida_warranty_parts_control_enabled();
drop function if exists public.aida_warranty_enabled();
drop function if exists public.aida_warranty_days();

drop index if exists public.idx_tickets_warranty_source_claim_unique;
drop index if exists public.idx_tickets_warranty_origin_active;
drop index if exists public.idx_tickets_warranty_origin_id;
drop index if exists public.idx_tickets_warranty_converted_id;
drop index if exists public.idx_tickets_warranty_coverage;

alter table public.tickets
    drop constraint if exists tickets_warranty_converted_ticket_id_fkey,
    drop constraint if exists tickets_warranty_source_claim_id_fkey,
    drop constraint if exists tickets_warranty_origin_ticket_id_fkey,
    drop constraint if exists tickets_warranty_shape_check,
    drop constraint if exists tickets_warranty_dates_check,
    drop constraint if exists tickets_warranty_days_check,
    drop constraint if exists tickets_warranty_status_check,
    drop column if exists warranty_decided_by_name,
    drop column if exists warranty_decided_by,
    drop column if exists warranty_decided_at,
    drop column if exists warranty_needs_parts,
    drop column if exists warranty_technical_report,
    drop column if exists warranty_expires_at,
    drop column if exists warranty_start_at,
    drop column if exists warranty_days,
    drop column if exists warranty_status,
    drop column if exists warranty_converted_ticket_id,
    drop column if exists warranty_source_claim_id,
    drop column if exists warranty_origin_ticket_id,
    drop column if exists warranty_claim;

commit;
