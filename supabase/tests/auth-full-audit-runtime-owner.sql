-- Local runtime alignment only. Supabase executes migrations as postgres;
-- the portable test bootstrap uses a separate administrator.
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
    OR inet_server_port()<>54329
    OR current_database() NOT LIKE 'aida_auth_review_%' THEN
  RAISE EXCEPTION 'Named loopback synthetic database required';
 END IF;
END $$;
ALTER FUNCTION private.can_upload_ticket_photo(text) OWNER TO postgres;
ALTER FUNCTION public.conclude_ticket_test(uuid,text,jsonb) OWNER TO postgres;
