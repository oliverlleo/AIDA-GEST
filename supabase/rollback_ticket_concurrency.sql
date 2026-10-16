-- Restore the pre-concurrency function projections before dropping the column.
-- Rows and operational fields are preserved. Apply after workspace-sync rollback.
BEGIN;
DROP TRIGGER zzzz_aida_ticket_revision ON public.tickets;
DROP FUNCTION private.enforce_ticket_revision();
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
   v_after:=replace(v_before,'t.id, t.revision,','t.id,');
   v_after:=replace(v_after,'''id'', t.id, ''revision'', t.revision,','''id'', t.id,');
   v_after:=replace(v_after,'''id'', pr.id, ''revision'', pr.revision,','''id'', pr.id,');
   v_after:=replace(v_after,'''id'', vr.id, ''revision'', vr.revision,','''id'', vr.id,');
   IF v_after=v_before THEN RAISE EXCEPTION 'Ticket revision rollback projection not found: %',v_name;END IF;
   EXECUTE v_after;
 END LOOP;
END $$;
ALTER TABLE public.tickets DROP CONSTRAINT tickets_revision_positive;
ALTER TABLE public.tickets DROP COLUMN revision;
NOTIFY pgrst,'reload schema';
COMMIT;
