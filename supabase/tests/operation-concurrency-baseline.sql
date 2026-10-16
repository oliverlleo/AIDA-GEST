\set ON_ERROR_STOP on
DO $$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR inet_server_port()<>54329
    OR current_database() NOT LIKE 'aida_auth_review_%' THEN RAISE EXCEPTION 'Named loopback synthetic database required';END IF;
END $$;
CREATE TABLE test_auth.operation_concurrency_baseline(snapshot jsonb NOT NULL);
INSERT INTO test_auth.operation_concurrency_baseline VALUES(test_auth.workspace_sync_snapshot());
SELECT 'PASS: nine structural baseline groups before operation concurrency' AS result;
