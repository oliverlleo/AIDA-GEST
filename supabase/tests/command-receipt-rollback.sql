\set ON_ERROR_STOP on
SELECT test_auth.assert((SELECT snapshot=test_auth.workspace_sync_snapshot() FROM test_auth.command_receipt_baseline),'all nine structural baseline groups exactly restored after command receipt rollback');
SELECT 'PASS: command receipt rollback exact metadata equivalence' AS result;
