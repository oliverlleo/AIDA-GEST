DO $$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'Loopback test only';END IF;END $$;
SELECT test_auth.assert((SELECT revision=2 AND tech_notes='first user saved' FROM public.tickets WHERE id='6f000000-0000-4000-8000-000000000002'),'two overlapping sessions produce one commit and one conflict');
SELECT 'PASS: concurrent old-version edit rejected after row-lock wait, first edit retained' AS result;
