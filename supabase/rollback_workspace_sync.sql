-- Revert only workspace invalidation hints. No business rows, grants, RLS policies,
-- existing triggers or Realtime publications are changed or restored from copies.
BEGIN;
DROP POLICY IF EXISTS aida_workspace_sync_receive ON realtime.messages;
DO $triggers$
DECLARE v record;
BEGIN
 FOR v IN SELECT n.nspname,c.relname,t.tgname
  FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND t.tgname='aida_workspace_sync' AND NOT t.tgisinternal
   AND t.tgfoid=to_regprocedure('private.emit_workspace_sync()') LOOP
  EXECUTE format('DROP TRIGGER %I ON %I.%I',v.tgname,v.nspname,v.relname);
 END LOOP;
END $triggers$;
DROP FUNCTION IF EXISTS private.emit_workspace_sync();
DROP FUNCTION IF EXISTS private.publish_workspace_sync(uuid,text);
DROP FUNCTION IF EXISTS private.can_receive_workspace_sync(text);
COMMIT;
