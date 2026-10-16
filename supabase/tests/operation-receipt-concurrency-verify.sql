\set ON_ERROR_STOP on
SELECT test_auth.assert((SELECT revision=2 AND status='partial' FROM public.inventory_purchases WHERE id='94cb3619-0000-4000-8000-000000000012'),'partial receipt race saved exactly one purchase update');
SELECT test_auth.assert((SELECT received_quantity=2 FROM public.inventory_purchase_items WHERE id='94cb3619-0000-4000-8000-000000000013'),'two attempts received two units once, not four');
SELECT test_auth.assert((SELECT physical_quantity=2 FROM public.inventory_balances WHERE item_id='94cb3619-0000-4000-8000-000000000010' AND location_id='94cb3619-0000-4000-8000-000000000011'),'stock matches one partial receipt');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.inventory_movements WHERE purchase_id='94cb3619-0000-4000-8000-000000000012'),'single movement despite concurrent receipt attempts');
SELECT 'PASS: two-session partial receipt CAS and side effects' AS result;
