\set ON_ERROR_STOP on
SELECT test_auth.assert((SELECT revision=2 AND scheduled_start=(current_date+30+time '11:00') AT TIME ZONE 'America/Sao_Paulo' FROM public.ticket_appointments WHERE id='94cb3619-0000-4000-8000-000000000021'),'first reschedule wins and second cannot overwrite');
SELECT test_auth.assert((SELECT count(*)=1 FROM public.ticket_logs WHERE ticket_id='94cb3619-0000-4000-8000-000000000020' AND action='Remarcou Análise'),'exactly one reschedule log');
SELECT 'PASS: two-session reschedule CAS and single audit event' AS result;
