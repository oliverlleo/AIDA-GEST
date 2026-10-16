-- Compare-and-swap for browser snapshots; current server workflows retain their
-- transactional locks and state checks. No operational row is removed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
ALTER TABLE public.tickets ADD COLUMN revision bigint NOT NULL DEFAULT 1;
ALTER TABLE public.tickets ADD CONSTRAINT tickets_revision_positive CHECK (revision > 0);

CREATE FUNCTION private.enforce_ticket_revision()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE
 v_method text:=upper(coalesce(current_setting('request.method',true),''));
 v_path text:=coalesce(current_setting('request.path',true),'');
 v_headers jsonb;v_version jsonb;v_expected bigint;v_expected_id uuid;
 v_checked jsonb:=coalesce(nullif(current_setting('aida.checked_ticket_versions',true),''),'{}')::jsonb;
 v_role text:=coalesce(auth.role(),'');v_trusted_command boolean:=false;
BEGIN
 IF TG_OP='INSERT' THEN NEW.revision:=1;RETURN NEW;END IF;

 -- API callers cannot write a revision chosen by the browser, including admins.
 IF TG_OP='UPDATE' AND NEW.revision IS DISTINCT FROM OLD.revision THEN
   RAISE EXCEPTION 'A revisao da OS e controlada pelo servidor.' USING ERRCODE='42501';
 END IF;

 -- PostgREST sets these request settings itself. SQL maintenance and service
 -- jobs have no browser snapshot, but still advance the revision below.
 IF v_role IN ('anon','authenticated') AND v_method IN ('PATCH','POST','DELETE','PUT') THEN
   BEGIN
     v_headers:=coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
     v_version:=nullif(v_headers->>'x-aida-ticket-version','')::jsonb;
     IF v_version IS NOT NULL THEN
       IF jsonb_typeof(v_version)<>'object' OR (v_version->>'revision') !~ '^[0-9]{1,18}$' THEN
         RAISE invalid_parameter_value;
       END IF;
       v_expected_id:=(v_version->>'id')::uuid;
       v_expected:=(v_version->>'revision')::bigint;
       IF v_expected_id IS NULL OR v_expected IS NULL OR v_expected<1 THEN RAISE invalid_parameter_value; END IF;
     END IF;
   EXCEPTION WHEN OTHERS THEN
     RAISE EXCEPTION 'Versao de edicao invalida. Reabra a OS antes de salvar.' USING ERRCODE='PT409';
   END;

   -- Explicit audited transaction roots only. The function must actually run
   -- through its privileged implementation; a direct table PATCH is never exempt.
   v_trusted_command:=current_user NOT IN ('anon','authenticated') AND v_method='POST' AND v_path=ANY(ARRAY[
     '/rpc/start_ticket_analysis','/rpc/start_repair_timer','/rpc/complete_repair_with_timer',
     '/rpc/pause_repair_for_parts','/rpc/resume_repair_after_parts','/rpc/conclude_ticket_test',
     '/rpc/complete_warranty_analysis','/rpc/complete_warranty_analysis_with_inventory',
     '/rpc/link_warranty_paid_ticket','/rpc/request_ticket_inventory_parts',
     '/rpc/approve_ticket_with_inventory','/rpc/complete_repair_with_inventory',
     '/rpc/create_inventory_purchase','/rpc/receive_inventory_purchase',
     '/rpc/allocate_received_inventory_purchase','/rpc/cancel_inventory_purchase',
     '/rpc/return_ticket_inventory','/rpc/create_ticket_appointment','/rpc/reschedule_ticket_appointment',
     '/rpc/cancel_ticket_appointment','/rpc/start_ticket_appointment','/rpc/complete_ticket_appointment',
     '/rpc/create_ticket_with_optional_analysis_schedule','/rpc/update_workspace_tracker_config'
   ]);
   -- The inventory configuration trigger locks/updates affected OS atomically.
   IF current_user NOT IN ('anon','authenticated') AND v_path='/workspaces'
      AND v_method='PATCH' AND pg_trigger_depth()>1 THEN v_trusted_command:=true;END IF;

   IF v_expected_id=OLD.id THEN
     -- The row is already locked by the UPDATE/DELETE statement. Two requests
     -- carrying the same revision cannot both pass after the lock is released.
     IF NOT(v_checked ? OLD.id::text) THEN
       IF v_expected IS DISTINCT FROM OLD.revision THEN
         RAISE EXCEPTION 'Esta OS foi atualizada em outro acesso. Revise as alteracoes antes de salvar novamente.'
           USING ERRCODE='PT409',DETAIL=jsonb_build_object('ticket_id',OLD.id,'current_revision',OLD.revision)::text;
       END IF;
       PERFORM set_config('aida.checked_ticket_versions',
         (v_checked||jsonb_build_object(OLD.id::text,v_expected))::text,true);
     ELSIF (v_checked->>OLD.id::text)::bigint IS DISTINCT FROM v_expected THEN
       RAISE EXCEPTION 'Versao de edicao inconsistente.' USING ERRCODE='PT409';
     END IF;
   ELSIF NOT v_trusted_command THEN
     RAISE EXCEPTION 'Atualize a pagina e reabra esta OS para revisar a versao atual antes de salvar.' USING ERRCODE='PT409';
   END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;
 NEW.revision:=OLD.revision+1;
 RETURN NEW;
END $$;
ALTER FUNCTION private.enforce_ticket_revision() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.enforce_ticket_revision() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER zzzz_aida_ticket_revision BEFORE INSERT OR UPDATE OR DELETE ON public.tickets
 FOR EACH ROW EXECUTE FUNCTION private.enforce_ticket_revision();

-- Keep the existing bounded projections, filters, RLS and RPC signatures. Only
-- add the revision beside the id in their existing ticket DTOs.
DO $$
DECLARE v_name text;v_oid oid;v_before text;v_after text;
BEGIN
 FOREACH v_name IN ARRAY ARRAY[
   'get_ticket_cards_page','get_operational_ticket_page','get_test_bench_page',
   'get_unscheduled_ticket_page','get_customer_ticket_page','get_warranty_eligible_tickets',
   'get_inventory_item_reservations_page','get_overview_extra_queue_page',
   'get_warranty_ticket_summaries','get_ticket_inventory_summaries','get_ticket_inventory_budget_cost_summaries'
 ] LOOP
   SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=v_name;
   v_before:=pg_get_functiondef(v_oid);
   v_after:=regexp_replace(v_before,'(select[[:space:]]+)t\.id,','\1t.id, t.revision,','gi');
   v_after:=replace(v_after,'''id'', t.id,','''id'', t.id, ''revision'', t.revision,');
   v_after:=replace(v_after,'''id'', pr.id,','''id'', pr.id, ''revision'', pr.revision,');
   v_after:=replace(v_after,'''id'', vr.id,','''id'', vr.id, ''revision'', vr.revision,');
   IF v_after=v_before THEN RAISE EXCEPTION 'Ticket revision projection not found: %',v_name;END IF;
   EXECUTE v_after;
 END LOOP;
 -- get_operational_queue/get_overview_queue_page already project t.*;
 -- get_overview_extra_queues delegates to the projection changed above.
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
