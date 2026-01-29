
-- Rollback Phase 4

ALTER FUNCTION public.create_owner_workspace_and_profile(text, text) RESET search_path;
ALTER FUNCTION public.log_ticket_changes() RESET search_path;
ALTER FUNCTION public.create_owner_workspace(text, text) RESET search_path;
ALTER FUNCTION public.get_client_ticket_details(uuid) RESET search_path;
