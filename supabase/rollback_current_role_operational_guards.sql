-- Restore only the three operational guards to their audited previous definitions.
-- Supabase Auth, memberships, invitations and all records remain in place.
BEGIN;
CREATE OR REPLACE FUNCTION private.complete_ticket_appointment(p_ticket_id uuid, p_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_app record;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    IF p_type NOT IN ('analysis', 'repair') THEN
        RAISE EXCEPTION 'Tipo de agendamento inválido.';
    END IF;

    SELECT a.id, a.technician_id
      INTO v_app
      FROM public.ticket_appointments AS a
     WHERE a.workspace_id = v_ctx.workspace_id
       AND a.ticket_id = p_ticket_id
       AND a.appointment_type = p_type
       AND a.status IN ('scheduled', 'in_progress')
       AND a.deleted_at IS NULL
     ORDER BY a.created_at DESC
     LIMIT 1;

    IF v_app.id IS NULL THEN
        RETURN;
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND v_app.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode concluir agendamentos da própria agenda.';
    END IF;

    UPDATE public.ticket_appointments
       SET status = 'completed',
           actual_start = COALESCE(actual_start, timezone('utc', now())),
           actual_end = timezone('utc', now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id,
           updated_at = timezone('utc', now())
     WHERE id = v_app.id
       AND workspace_id = v_ctx.workspace_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.start_ticket_appointment(p_ticket_id uuid, p_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_app record;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    IF p_type NOT IN ('analysis', 'repair') THEN
        RAISE EXCEPTION 'Tipo de agendamento inválido.';
    END IF;

    SELECT a.id, a.technician_id
      INTO v_app
      FROM public.ticket_appointments AS a
     WHERE a.workspace_id = v_ctx.workspace_id
       AND a.ticket_id = p_ticket_id
       AND a.appointment_type = p_type
       AND a.status = 'scheduled'
       AND a.deleted_at IS NULL
     ORDER BY a.created_at DESC
     LIMIT 1;

    IF v_app.id IS NULL THEN
        RETURN;
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND v_app.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode iniciar agendamentos da própria agenda.';
    END IF;

    UPDATE public.ticket_appointments
       SET status = 'in_progress',
           actual_start = COALESCE(actual_start, timezone('utc', now())),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id,
           updated_at = timezone('utc', now())
     WHERE id = v_app.id
       AND workspace_id = v_ctx.workspace_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_repair_timer(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'A OS não está disponível para iniciar reparo.';
    END IF;
    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode iniciar o próprio reparo.';
    END IF;
    IF v_ticket.repair_start_at IS NOT NULL THEN
        RAISE EXCEPTION 'O reparo já está em andamento.';
    END IF;

    IF public.aida_config_bool(v_config, 'modules', 'agenda', true)
       AND public.aida_ticket_field_mode(v_config, 'repair_schedule', false) = 'required'
       AND NOT EXISTS (
           SELECT 1 FROM public.ticket_appointments a
            WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
              AND a.appointment_type = 'repair' AND a.status IN ('scheduled', 'in_progress')
              AND a.deleted_at IS NULL
       ) THEN
        RAISE EXCEPTION 'Agende o reparo antes de iniciar o serviço.';
    END IF;

    UPDATE public.tickets SET repair_start_at = now(), repair_paused_at = NULL, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
       SET status = 'in_progress', actual_start = COALESCE(actual_start, now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'repair' AND a.status = 'scheduled' AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Iniciou Execução', format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — iniciado por **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name), v_ctx.actor_name);
    RETURN jsonb_build_object('success', true);
END;
$function$;
COMMIT;
