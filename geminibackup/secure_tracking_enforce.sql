-- Grant execute on the new secure RPC to anon (public)
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details_public(uuid, uuid) TO public;

-- Revoke execute on the old insecure RPC from everyone except service_role
REVOKE EXECUTE ON FUNCTION public.get_client_ticket_details(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_client_ticket_details(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_client_ticket_details(uuid) FROM authenticated;

-- Ensure service_role can still use it (optional, for internal admin tasks if any)
GRANT EXECUTE ON FUNCTION public.get_client_ticket_details(uuid) TO service_role;
