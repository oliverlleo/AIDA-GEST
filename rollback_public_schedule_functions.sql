-- Emergency rollback for harden_public_schedule_functions.sql.
-- Restores the original implementations to public and their previous grants.

begin;

drop function if exists public.get_schedule_availability(uuid, text, date, integer);
drop function if exists public.get_unscheduled_tickets(uuid, text, text, integer, integer);
drop function if exists public.get_schedule_dashboard(uuid, text, date);
drop function if exists public.get_ticket_appointments(uuid);
drop function if exists public.create_ticket_with_optional_analysis_schedule(jsonb, jsonb);
drop function if exists public.create_ticket_appointment(uuid, uuid, text, timestamptz, timestamptz, text);
drop function if exists public.create_schedule_block(uuid, text, timestamptz, timestamptz, boolean, text, jsonb, text);
drop function if exists public.delete_schedule_block(uuid);

alter function private.get_schedule_availability(uuid, text, date, integer) set schema public;
alter function private.get_unscheduled_tickets(uuid, text, text, integer, integer) set schema public;
alter function private.get_schedule_dashboard(uuid, text, date) set schema public;
alter function private.get_ticket_appointments(uuid) set schema public;
alter function private.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) set schema public;
alter function private.create_ticket_appointment(uuid, uuid, text, timestamptz, timestamptz, text) set schema public;
alter function private.create_schedule_block(uuid, text, timestamptz, timestamptz, boolean, text, jsonb, text) set schema public;
alter function private.delete_schedule_block(uuid) set schema public;

-- Restore the grants captured before this stage.
grant execute on function public.get_schedule_availability(uuid, text, date, integer) to public, anon, authenticated, service_role;
grant execute on function public.get_unscheduled_tickets(uuid, text, text, integer, integer) to public, anon, authenticated, service_role;
grant execute on function public.get_ticket_appointments(uuid) to public, anon, authenticated, service_role;
grant execute on function public.get_schedule_dashboard(uuid, text, date) to anon, authenticated, service_role;
grant execute on function public.create_ticket_with_optional_analysis_schedule(jsonb, jsonb) to anon, authenticated, service_role;
grant execute on function public.create_ticket_appointment(uuid, uuid, text, timestamptz, timestamptz, text) to anon, authenticated, service_role;
grant execute on function public.create_schedule_block(uuid, text, timestamptz, timestamptz, boolean, text, jsonb, text) to anon, authenticated, service_role;
grant execute on function public.delete_schedule_block(uuid) to anon, authenticated, service_role;

grant execute on function public.cancel_ticket_appointment(uuid, text) to anon, authenticated, service_role;
grant execute on function public.reschedule_ticket_appointment(uuid, uuid, timestamptz, timestamptz, text) to anon, authenticated, service_role;
grant execute on function public.get_technician_schedule(uuid, text, date) to anon, authenticated, service_role;
grant execute on function public.start_ticket_appointment(uuid, text) to public, anon, authenticated, service_role;
grant execute on function public.complete_ticket_appointment(uuid, text) to public, anon, authenticated, service_role;

grant execute on function public.get_ticket_appointments_state(uuid, uuid) to public, anon, authenticated, service_role;
grant execute on function public.get_expanded_blocks(uuid, uuid, date, date) to anon, authenticated, service_role;
grant execute on function public.validate_appointment_capacity(uuid, uuid, timestamptz, timestamptz, uuid) to anon, authenticated, service_role;
grant execute on function public.enforce_configurable_appointment() to service_role;
grant execute on function public.sync_ticket_schedule_state() to public, anon, authenticated, service_role;
grant execute on function public.set_schedule_updated_at() to anon, authenticated, service_role;

commit;
