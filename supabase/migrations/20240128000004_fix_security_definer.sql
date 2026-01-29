
-- Phase 4: Fix remaining SECURITY DEFINER functions

ALTER FUNCTION public.create_owner_workspace_and_profile(text, text) SET search_path = public, extensions, pg_catalog;
ALTER FUNCTION public.log_ticket_changes() SET search_path = public, extensions, pg_catalog;
ALTER FUNCTION public.create_owner_workspace(text, text) SET search_path = public, extensions, pg_catalog;
ALTER FUNCTION public.get_client_ticket_details(uuid) SET search_path = public, extensions, pg_catalog;
