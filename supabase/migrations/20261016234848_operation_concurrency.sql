-- Protect incremental purchase receipts and appointment edits from stale forms.
-- Existing row locks still serialize business work; this comparison rejects the
-- second stale intent rather than treating it as another valid partial receipt.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
ALTER TABLE public.inventory_purchases ADD COLUMN revision bigint NOT NULL DEFAULT 1;
ALTER TABLE public.inventory_purchases ADD CONSTRAINT inventory_purchases_revision_positive CHECK(revision>0);
ALTER TABLE public.ticket_appointments ADD COLUMN revision bigint NOT NULL DEFAULT 1;
ALTER TABLE public.ticket_appointments ADD CONSTRAINT ticket_appointments_revision_positive CHECK(revision>0);

CREATE FUNCTION private.enforce_operation_revision()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE v_method text:=upper(coalesce(current_setting('request.method',true),''));
 v_path text:=coalesce(current_setting('request.path',true),'');
 v_role text:=coalesce(auth.role(),'');v_headers jsonb;v_version jsonb;
 v_resource text;v_id uuid;v_revision bigint;v_required boolean;v_key text;
 v_checked jsonb:=coalesce(nullif(current_setting('aida.checked_operation_versions',true),''),'{}')::jsonb;
BEGIN
 IF TG_OP='INSERT' THEN NEW.revision:=1;RETURN NEW;END IF;
 IF TG_OP='UPDATE' AND NEW.revision IS DISTINCT FROM OLD.revision THEN
  RAISE EXCEPTION 'A revisao da operacao e controlada pelo servidor.' USING ERRCODE='42501';
 END IF;
 IF v_role IN('anon','authenticated') AND v_method IN('POST','PATCH','PUT','DELETE') THEN
  v_required:=(v_path='/'||TG_TABLE_NAME)
   OR (TG_TABLE_NAME='inventory_purchases' AND v_path='/rpc/receive_inventory_purchase')
   OR (TG_TABLE_NAME='ticket_appointments' AND v_path='/rpc/reschedule_ticket_appointment');
  BEGIN
   v_headers:=coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
   v_version:=nullif(v_headers->>'x-aida-operation-version','')::jsonb;
   IF v_version IS NOT NULL THEN
    IF jsonb_typeof(v_version)<>'object'
       OR coalesce(v_version->>'resource','') NOT IN('inventory_purchases','ticket_appointments')
       OR coalesce(v_version->>'revision','') !~ '^[1-9][0-9]{0,17}$' THEN
     RAISE invalid_parameter_value;
    END IF;
    v_resource:=v_version->>'resource';
    v_id:=(v_version->>'id')::uuid;
    v_revision:=(v_version->>'revision')::bigint;
    IF v_id IS NULL THEN RAISE invalid_parameter_value;END IF;
   END IF;
  EXCEPTION WHEN OTHERS THEN
   RAISE EXCEPTION 'Versao da operacao invalida. Reabra o formulario antes de salvar.' USING ERRCODE='PT409';
  END;
  IF v_resource=TG_TABLE_NAME AND v_id=OLD.id THEN
   -- Business roots lock these rows before changing stock or the schedule. A
   -- conflict here rolls back every side effect of that same transaction.
   v_key:=TG_TABLE_NAME||':'||OLD.id::text;
   IF NOT(v_checked ? v_key) THEN
    IF v_revision IS DISTINCT FROM OLD.revision THEN
     RAISE EXCEPTION 'Esta operacao foi atualizada em outro acesso. Revise o formulario antes de confirmar.'
      USING ERRCODE='PT409',DETAIL=jsonb_build_object('resource',TG_TABLE_NAME,'id',OLD.id,'current_revision',OLD.revision)::text;
    END IF;
    PERFORM set_config('aida.checked_operation_versions',(v_checked||jsonb_build_object(v_key,v_revision))::text,true);
   ELSIF (v_checked->>v_key)::bigint IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION 'Versao da operacao inconsistente.' USING ERRCODE='PT409';
   END IF;
  ELSIF v_required THEN
   RAISE EXCEPTION 'Atualize a pagina e reabra o formulario para revisar a versao atual antes de confirmar.' USING ERRCODE='PT409';
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;
 NEW.revision:=OLD.revision+1;
 RETURN NEW;
END $$;
ALTER FUNCTION private.enforce_operation_revision() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.enforce_operation_revision() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER zzzz_aida_operation_revision BEFORE INSERT OR UPDATE OR DELETE ON public.inventory_purchases
 FOR EACH ROW EXECUTE FUNCTION private.enforce_operation_revision();
CREATE TRIGGER zzzz_aida_operation_revision BEFORE INSERT OR UPDATE OR DELETE ON public.ticket_appointments
 FOR EACH ROW EXECUTE FUNCTION private.enforce_operation_revision();
-- Purchase detail already uses to_jsonb(v_purchase). The two appointment lists
-- have bounded explicit projections; preserve them and add only the version.
DO $projections$
DECLARE v_oid oid;v_before text;v_after text;
BEGIN
 FOREACH v_oid IN ARRAY ARRAY['public.get_technician_schedule(uuid,text,date)'::regprocedure::oid,
                              'private.get_ticket_appointments(uuid)'::regprocedure::oid] LOOP
  v_before:=pg_get_functiondef(v_oid);
  v_after:=replace(v_before,'SELECT a.id,','SELECT a.id, a.revision,');
  IF v_after=v_before THEN RAISE EXCEPTION 'Appointment revision projection not found: %',v_oid::regprocedure;END IF;
  EXECUTE v_after;
 END LOOP;
END $projections$;
NOTIFY pgrst,'reload schema';
COMMIT;
