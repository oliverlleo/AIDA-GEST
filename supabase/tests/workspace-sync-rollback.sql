\set ON_ERROR_STOP on
SELECT test_auth.assert((SELECT snapshot=test_auth.workspace_sync_snapshot() FROM test_auth.workspace_sync_baseline),'all nine baseline metadata groups exactly restored after sync rollback');
SELECT test_auth.assert(to_regprocedure('private.can_receive_workspace_sync(text)') IS NULL AND to_regprocedure('private.publish_workspace_sync(uuid,text)') IS NULL AND to_regprocedure('private.emit_workspace_sync()') IS NULL,'three sync functions removed');
SELECT test_auth.assert(NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='aida_workspace_sync' AND NOT tgisinternal),'sync triggers removed');
SELECT 'PASS: workspace sync rollback exact metadata equivalence' AS result;
