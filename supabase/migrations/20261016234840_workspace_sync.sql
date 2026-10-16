-- Database-originated invalidations only. Business rows never travel through Realtime.
-- Realtime joins cache access, so every refreshed view still uses the existing live
-- membership/RLS checks. Reconnect/focus and bounded foreground catch-up cover lost hints.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $guard$
BEGIN
 IF to_regprocedure('realtime.send(jsonb,text,text,boolean)') IS NULL
    OR to_regprocedure('realtime.topic()') IS NULL
    OR NOT coalesce((SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid=to_regclass('realtime.messages')),false) THEN
  RAISE EXCEPTION 'Managed Realtime send/topic and messages RLS must already exist';
 END IF;
 IF to_regprocedure('private.can_receive_workspace_sync(text)') IS NOT NULL
    OR to_regprocedure('private.publish_workspace_sync(uuid,text)') IS NOT NULL
    OR to_regprocedure('private.emit_workspace_sync()') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname='realtime' AND tablename='messages' AND policyname='aida_workspace_sync_receive')
    OR EXISTS(SELECT 1 FROM pg_catalog.pg_trigger WHERE tgname='aida_workspace_sync' AND NOT tgisinternal) THEN
  RAISE EXCEPTION 'Workspace sync objects already exist; review migration history';
 END IF;
END $guard$;

CREATE FUNCTION private.can_receive_workspace_sync(p_topic text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_workspace uuid;
BEGIN
 IF p_topic IS NULL OR p_topic !~ '^workspace:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN false; END IF;
 v_workspace:=substring(p_topic FROM 11)::uuid;
 -- No browser-selected x-workspace-id is trusted or required for a WebSocket join.
 RETURN EXISTS(SELECT 1 FROM private.workspace_actor(v_workspace));
EXCEPTION WHEN OTHERS THEN RETURN false;
END $$;
ALTER FUNCTION private.can_receive_workspace_sync(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.can_receive_workspace_sync(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.can_receive_workspace_sync(text) TO authenticated;

-- Do not ALTER the managed realtime schema/table. RLS is already enabled there;
-- policy statements are the supported exception to the managed-schema DDL lock.
CREATE POLICY aida_workspace_sync_receive ON realtime.messages
 FOR SELECT TO authenticated USING (
  extension='broadcast' AND "private" IS TRUE
  AND topic=(SELECT realtime.topic())
  AND private.can_receive_workspace_sync((SELECT realtime.topic()))
 );
-- No INSERT policy: clients cannot fabricate invalidations or publish on this channel.

CREATE FUNCTION private.publish_workspace_sync(p_workspace uuid,p_scope text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_seen jsonb; v_key text;
BEGIN
 IF p_workspace IS NULL OR p_scope IS NULL OR p_scope NOT IN ('tickets','inventory','notes','notifications','access','agenda') THEN RETURN; END IF;
 -- Coalesce cascades and bulk mutations to one hint per workspace/scope/transaction.
 -- This state is transaction local, creates no persistent business or audit rows,
 -- and rolls back with the business mutation.
 v_seen:=coalesce(nullif(pg_catalog.current_setting('aida.workspace_sync_seen',true),'')::jsonb,'{}'::jsonb);
 v_key:=p_workspace::text||':'||p_scope;
 IF v_seen ? v_key THEN RETURN; END IF;
 PERFORM pg_catalog.set_config('aida.workspace_sync_seen',(v_seen||jsonb_build_object(v_key,true))::text,true);
 PERFORM realtime.send(jsonb_build_object('scope',p_scope),'invalidate','workspace:'||p_workspace::text,true);
EXCEPTION WHEN OTHERS THEN
 -- Synchronization is a hint, never a reason to lose an otherwise valid mutation.
 -- No row content, customer data, identifiers or original error text enter this warning.
 RAISE WARNING 'Workspace synchronization hint unavailable';
END $$;
ALTER FUNCTION private.publish_workspace_sync(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.publish_workspace_sync(uuid,text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.emit_workspace_sync()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_new jsonb:='{}'::jsonb; v_old jsonb:='{}'::jsonb;
 v_workspaces uuid[]; v_links uuid[]; v_workspace uuid; v_scope text;
BEGIN
 IF TG_OP<>'DELETE' THEN v_new:=to_jsonb(NEW); END IF;
 IF TG_OP<>'INSERT' THEN v_old:=to_jsonb(OLD); END IF;
 CASE TG_ARGV[1]
  WHEN 'workspace_id' THEN
   v_workspaces:=ARRAY[(v_new->>'workspace_id')::uuid,(v_old->>'workspace_id')::uuid];
  WHEN 'workspace' THEN
   v_workspaces:=ARRAY[(v_new->>'id')::uuid,(v_old->>'id')::uuid];
  WHEN 'ticket' THEN
   v_links:=ARRAY[(v_new->>'ticket_id')::uuid,(v_old->>'ticket_id')::uuid];
   SELECT array_agg(DISTINCT t.workspace_id) INTO v_workspaces FROM public.tickets t WHERE t.id=ANY(v_links);
  WHEN 'employee' THEN
   v_links:=ARRAY[(v_new->>'employee_id')::uuid,(v_old->>'employee_id')::uuid];
   SELECT array_agg(DISTINCT e.workspace_id) INTO v_workspaces FROM public.employees e WHERE e.id=ANY(v_links);
  ELSE RETURN NULL;
 END CASE;
 FOR v_workspace IN SELECT DISTINCT w FROM unnest(v_workspaces) w WHERE w IS NOT NULL LOOP
  FOREACH v_scope IN ARRAY string_to_array(TG_ARGV[0],',') LOOP
   PERFORM private.publish_workspace_sync(v_workspace,v_scope);
  END LOOP;
 END LOOP;
 RETURN NULL;
EXCEPTION WHEN OTHERS THEN
 RAISE WARNING 'Workspace synchronization hint unavailable';
 RETURN NULL;
END $$;
ALTER FUNCTION private.emit_workspace_sync() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.emit_workspace_sync() FROM PUBLIC,anon,authenticated;

DO $triggers$
DECLARE v record;
BEGIN
 FOR v IN SELECT * FROM (VALUES
  ('tickets','tickets,agenda,notifications','workspace_id'),
  ('ticket_logs','tickets','ticket'),
  ('customers','tickets','workspace_id'),
  ('internal_notes','notes','workspace_id'),
  ('notifications','notifications','ticket'),
  ('ticket_appointments','agenda,tickets','workspace_id'),
  ('technician_schedule_settings','agenda','workspace_id'),
  ('technician_schedule_blocks','agenda','workspace_id'),
  ('ticket_part_items','inventory,tickets','workspace_id'),
  ('inventory_items','inventory','workspace_id'),
  ('inventory_balances','inventory','workspace_id'),
  ('inventory_item_costs','inventory','workspace_id'),
  ('inventory_item_models','inventory','workspace_id'),
  ('inventory_item_relations','inventory','workspace_id'),
  ('inventory_item_suppliers','inventory','workspace_id'),
  ('inventory_location_groups','inventory','workspace_id'),
  ('inventory_location_schemes','inventory','workspace_id'),
  ('inventory_locations','inventory','workspace_id'),
  ('inventory_movements','inventory','workspace_id'),
  ('inventory_purchase_allocations','inventory','workspace_id'),
  ('inventory_purchase_items','inventory','workspace_id'),
  ('inventory_purchases','inventory','workspace_id'),
  ('inventory_reservations','inventory','workspace_id'),
  ('workspaces','access','workspace'),
  ('employees','access','workspace_id'),
  ('employee_auth_state','access','employee'),
  ('workspace_memberships','access','workspace_id'),
  ('workspace_invitations','access','workspace_id'),
  ('checklist_templates','access','workspace_id'),
  ('device_models','access','workspace_id'),
  ('defects','access','workspace_id'),
  ('defect_options','access','workspace_id'),
  ('suppliers','access','workspace_id'),
  ('fornecedores','access','workspace_id'),
  ('outsourced_companies','access','workspace_id'),
  ('terceirizados','access','workspace_id')
 ) t(table_name,scopes,source) LOOP
  EXECUTE format('CREATE TRIGGER aida_workspace_sync AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION private.emit_workspace_sync(%L,%L)',v.table_name,v.scopes,v.source);
 END LOOP;
END $triggers$;
COMMIT;
