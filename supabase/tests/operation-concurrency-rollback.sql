\set ON_ERROR_STOP on
SELECT test_auth.assert((SELECT snapshot=test_auth.workspace_sync_snapshot() FROM test_auth.operation_concurrency_baseline),'all nine structural baseline groups exactly restored after operation rollback');
SELECT 'PASS: operation concurrency rollback exact metadata equivalence' AS result;
