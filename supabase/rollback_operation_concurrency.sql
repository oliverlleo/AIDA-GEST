-- Revert only optimistic operation versions. Business rows and their fields remain.
BEGIN;
DROP TRIGGER zzzz_aida_operation_revision ON public.inventory_purchases;
DROP TRIGGER zzzz_aida_operation_revision ON public.ticket_appointments;
DROP FUNCTION private.enforce_operation_revision();
DO $projections$
DECLARE v_oid oid;v_before text;v_after text;
BEGIN
 FOREACH v_oid IN ARRAY ARRAY['public.get_technician_schedule(uuid,text,date)'::regprocedure::oid,
                              'private.get_ticket_appointments(uuid)'::regprocedure::oid] LOOP
  v_before:=pg_get_functiondef(v_oid);
  v_after:=replace(v_before,'SELECT a.id, a.revision,','SELECT a.id,');
  IF v_after=v_before THEN RAISE EXCEPTION 'Appointment revision rollback projection not found: %',v_oid::regprocedure;END IF;
  EXECUTE v_after;
 END LOOP;
END $projections$;
ALTER TABLE public.inventory_purchases DROP CONSTRAINT inventory_purchases_revision_positive;
ALTER TABLE public.inventory_purchases DROP COLUMN revision;
ALTER TABLE public.ticket_appointments DROP CONSTRAINT ticket_appointments_revision_positive;
ALTER TABLE public.ticket_appointments DROP COLUMN revision;
NOTIFY pgrst,'reload schema';
COMMIT;
