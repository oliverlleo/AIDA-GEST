-- Mantém a auditoria de agenda legível sem delegar identidade ou autorização ao navegador.
-- Os mesmos controles de workspace, papel e técnico continuam dentro das RPCs SECURITY DEFINER.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_current_actor_context()
RETURNS TABLE(
    workspace_id uuid,
    actor_user_id uuid,
    actor_employee_id uuid,
    actor_name text,
    actor_roles text[],
    actor_kind text,
    is_admin boolean,
    is_technician boolean,
    is_attendant boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_uid uuid;
    v_emp_id uuid;
    v_ws_id uuid;
    v_roles text[];
    v_name text;
    v_prof_ws uuid;
    v_prof_role text;
BEGIN
    v_uid := auth.uid();

    IF v_uid IS NOT NULL THEN
        SELECT id INTO v_ws_id
        FROM public.workspaces
        WHERE owner_id = v_uid
        LIMIT 1;

        IF v_ws_id IS NOT NULL THEN
            RETURN QUERY
            SELECT v_ws_id, v_uid, NULL::uuid, 'Administrador'::text,
                   ARRAY['admin']::text[], 'user'::text, true, false, false;
            RETURN;
        END IF;

        SELECT p.workspace_id, p.role
        INTO v_prof_ws, v_prof_role
        FROM public.profiles AS p
        WHERE p.id = v_uid
        LIMIT 1;

        IF v_prof_ws IS NOT NULL THEN
            RETURN QUERY
            SELECT v_prof_ws, v_uid, NULL::uuid, 'Administrador'::text,
                   ARRAY[v_prof_role]::text[], 'user'::text,
                   (v_prof_role = 'admin'), false, false;
            RETURN;
        END IF;
    END IF;

    SELECT t.employee_id, t.workspace_id, t.role
    INTO v_emp_id, v_ws_id, v_roles
    FROM public.current_employee_from_token() AS t
    LIMIT 1;

    IF v_ws_id IS NOT NULL THEN
        SELECT e.name
        INTO v_name
        FROM public.employees AS e
        WHERE e.id = v_emp_id
          AND e.workspace_id = v_ws_id
        LIMIT 1;

        RETURN QUERY
        SELECT v_ws_id, NULL::uuid, v_emp_id,
               COALESCE(v_name, 'Funcionário'), v_roles, 'employee'::text,
               ('admin' = ANY(v_roles)), ('tecnico' = ANY(v_roles)),
               ('atendente' = ANY(v_roles));
        RETURN;
    END IF;

    RAISE EXCEPTION 'Acesso negado: Contexto de ator não resolvido.';
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_ticket_appointment(
    p_ticket_id uuid,
    p_technician_id uuid,
    p_appointment_type text,
    p_scheduled_start timestamp with time zone,
    p_scheduled_end timestamp with time zone,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ws_id uuid;
    v_app_id uuid;
    v_log_action text;
    v_type_label text;
    v_ticket record;
    v_technician_name text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    IF p_appointment_type NOT IN ('analysis', 'repair') THEN
        RAISE EXCEPTION 'Tipo de agendamento inválido. Use analysis ou repair.';
    END IF;

    SELECT t.device_model, t.client_name
    INTO v_ticket
    FROM public.tickets AS t
    WHERE t.id = p_ticket_id
      AND t.workspace_id = v_ws_id
      AND t.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chamado não encontrado ou não pertence ao workspace.';
    END IF;

    SELECT e.name
    INTO v_technician_name
    FROM public.employees AS e
    WHERE e.id = p_technician_id
      AND e.workspace_id = v_ws_id
      AND e.deleted_at IS NULL;

    IF v_technician_name IS NULL THEN
        RAISE EXCEPTION 'Técnico não encontrado ou não pertence ao workspace.';
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND p_technician_id <> v_ctx.actor_employee_id
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode agendar na própria agenda.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.ticket_appointments AS a
        WHERE a.ticket_id = p_ticket_id
          AND a.workspace_id = v_ws_id
          AND a.deleted_at IS NULL
          AND a.status <> 'cancelled'
          AND a.appointment_type = p_appointment_type
    ) THEN
        RAISE EXCEPTION 'Já existe um agendamento de % ativo para este chamado. Use a função de remarcação.', p_appointment_type;
    END IF;

    PERFORM public.validate_appointment_capacity(
        v_ws_id, p_technician_id, p_scheduled_start, p_scheduled_end
    );

    INSERT INTO public.ticket_appointments (
        workspace_id, ticket_id, technician_id, appointment_type,
        scheduled_start, scheduled_end, notes,
        created_by_user_id, created_by_employee_id, status
    ) VALUES (
        v_ws_id, p_ticket_id, p_technician_id, p_appointment_type,
        p_scheduled_start, p_scheduled_end, p_notes,
        v_ctx.actor_user_id, v_ctx.actor_employee_id, 'scheduled'
    ) RETURNING id INTO v_app_id;

    IF p_appointment_type = 'repair' THEN
        UPDATE public.tickets
        SET technician_id = p_technician_id,
            updated_at = timezone('utc', now())
        WHERE id = p_ticket_id
          AND workspace_id = v_ws_id;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM public.ticket_appointments AS a
        WHERE a.ticket_id = p_ticket_id
          AND a.appointment_type = 'repair'
          AND a.status <> 'cancelled'
          AND a.deleted_at IS NULL
    ) THEN
        UPDATE public.tickets
        SET technician_id = p_technician_id,
            updated_at = timezone('utc', now())
        WHERE id = p_ticket_id
          AND workspace_id = v_ws_id;
    END IF;

    v_type_label := CASE WHEN p_appointment_type = 'analysis' THEN 'análise' ELSE 'reparo' END;
    v_log_action := CASE WHEN p_appointment_type = 'analysis' THEN 'Agendou Análise' ELSE 'Agendou Reparo' END;

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        p_ticket_id,
        v_log_action,
        format(
            'Agendamento de %s do aparelho %s do cliente %s criado com o técnico %s para %s, das %s às %s.',
            v_type_label,
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_technician_name,
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            to_char(p_scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')
        ),
        v_ctx.actor_name
    );

    RETURN jsonb_build_object('success', true, 'appointment_id', v_app_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.reschedule_ticket_appointment(
    p_appointment_id uuid,
    p_technician_id uuid,
    p_scheduled_start timestamp with time zone,
    p_scheduled_end timestamp with time zone,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ws_id uuid;
    v_app record;
    v_ticket record;
    v_new_technician_name text;
    v_type_label text;
    v_log_action text;
    v_details text;
    v_old_window text;
    v_new_window text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    SELECT * INTO v_app
    FROM public.ticket_appointments
    WHERE id = p_appointment_id
      AND workspace_id = v_ws_id
      AND deleted_at IS NULL
      AND status <> 'cancelled';

    IF v_app IS NULL THEN
        RAISE EXCEPTION 'Agendamento não encontrado, inativo ou já cancelado.';
    END IF;

    SELECT t.device_model, t.client_name, old_tech.name AS old_technician_name
    INTO v_ticket
    FROM public.tickets AS t
    LEFT JOIN public.employees AS old_tech
      ON old_tech.id = v_app.technician_id
     AND old_tech.workspace_id = v_ws_id
    WHERE t.id = v_app.ticket_id
      AND t.workspace_id = v_ws_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chamado não encontrado ou não pertence ao workspace.';
    END IF;

    SELECT e.name
    INTO v_new_technician_name
    FROM public.employees AS e
    WHERE e.id = p_technician_id
      AND e.workspace_id = v_ws_id
      AND e.deleted_at IS NULL;

    IF v_new_technician_name IS NULL THEN
        RAISE EXCEPTION 'Novo técnico não encontrado ou não pertence ao workspace.';
    END IF;

    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant THEN
        IF v_app.technician_id <> v_ctx.actor_employee_id
           OR p_technician_id <> v_ctx.actor_employee_id THEN
            RAISE EXCEPTION 'Acesso negado: Técnico só pode remarcar a própria agenda e não pode transferir para outro.';
        END IF;
    END IF;

    PERFORM public.validate_appointment_capacity(
        v_ws_id, p_technician_id, p_scheduled_start, p_scheduled_end, p_appointment_id
    );

    UPDATE public.ticket_appointments
    SET technician_id = p_technician_id,
        scheduled_start = p_scheduled_start,
        scheduled_end = p_scheduled_end,
        notes = COALESCE(p_notes, notes),
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = timezone('utc', now())
    WHERE id = p_appointment_id
      AND workspace_id = v_ws_id;

    IF v_app.appointment_type = 'repair' THEN
        UPDATE public.tickets
        SET technician_id = p_technician_id,
            updated_at = timezone('utc', now())
        WHERE id = v_app.ticket_id
          AND workspace_id = v_ws_id;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM public.ticket_appointments AS a
        WHERE a.ticket_id = v_app.ticket_id
          AND a.appointment_type = 'repair'
          AND a.status <> 'cancelled'
          AND a.deleted_at IS NULL
    ) THEN
        UPDATE public.tickets
        SET technician_id = p_technician_id,
            updated_at = timezone('utc', now())
        WHERE id = v_app.ticket_id
          AND workspace_id = v_ws_id;
    END IF;

    v_type_label := CASE WHEN v_app.appointment_type = 'analysis' THEN 'análise' ELSE 'reparo' END;
    v_log_action := CASE WHEN v_app.appointment_type = 'analysis' THEN 'Remarcou Análise' ELSE 'Remarcou Reparo' END;
    v_old_window := format(
        '%s das %s às %s',
        to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
        to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
        to_char(v_app.scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')
    );
    v_new_window := format(
        '%s das %s às %s',
        to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
        to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
        to_char(p_scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')
    );
    v_details := format(
        'Agendamento de %s do aparelho %s do cliente %s',
        v_type_label,
        COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado')
    );

    IF v_app.technician_id IS DISTINCT FROM p_technician_id THEN
        v_details := v_details || format(
            ' teve o técnico alterado de %s para %s',
            COALESCE(v_ticket.old_technician_name, 'não informado'),
            v_new_technician_name
        );
    ELSE
        v_details := v_details || format(
            ' manteve o técnico %s',
            v_new_technician_name
        );
    END IF;

    IF v_app.scheduled_start IS DISTINCT FROM p_scheduled_start
       OR v_app.scheduled_end IS DISTINCT FROM p_scheduled_end THEN
        v_details := v_details || format(
            '; data e horário alterados de %s para %s.',
            v_old_window,
            v_new_window
        );
    ELSE
        v_details := v_details || '.';
    END IF;

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (v_app.ticket_id, v_log_action, v_details, v_ctx.actor_name);

    RETURN jsonb_build_object('success', true, 'appointment_id', p_appointment_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_ticket_appointment(
    p_appointment_id uuid,
    p_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ws_id uuid;
    v_app record;
    v_ticket record;
    v_log_action text;
    v_type_label text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    SELECT * INTO v_app
    FROM public.ticket_appointments
    WHERE id = p_appointment_id
      AND workspace_id = v_ws_id
      AND deleted_at IS NULL
      AND status <> 'cancelled';

    IF v_app IS NULL THEN
        RAISE EXCEPTION 'Agendamento não encontrado, inativo ou já cancelado.';
    END IF;

    IF v_ctx.actor_kind = 'employee' AND NOT v_ctx.is_admin AND NOT v_ctx.is_attendant THEN
        IF v_app.technician_id <> v_ctx.actor_employee_id THEN
            RAISE EXCEPTION 'Acesso negado: Técnico só pode cancelar agendamentos da própria agenda.';
        END IF;
    END IF;

    SELECT t.device_model, t.client_name, e.name AS technician_name
    INTO v_ticket
    FROM public.tickets AS t
    LEFT JOIN public.employees AS e
      ON e.id = v_app.technician_id
     AND e.workspace_id = v_ws_id
    WHERE t.id = v_app.ticket_id
      AND t.workspace_id = v_ws_id;

    UPDATE public.ticket_appointments
    SET status = 'cancelled',
        notes = CASE WHEN p_reason IS NOT NULL THEN notes || E'\nCancelamento: ' || p_reason ELSE notes END,
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = timezone('utc', now())
    WHERE id = p_appointment_id;

    v_type_label := CASE WHEN v_app.appointment_type = 'analysis' THEN 'análise' ELSE 'reparo' END;
    v_log_action := CASE WHEN v_app.appointment_type = 'analysis' THEN 'Cancelou Análise' ELSE 'Cancelou Reparo' END;

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        v_app.ticket_id,
        v_log_action,
        format(
            'Agendamento de %s do aparelho %s do cliente %s com o técnico %s em %s, das %s às %s, foi cancelado%s.',
            v_type_label,
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            COALESCE(v_ticket.technician_name, 'não informado'),
            to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
            to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            to_char(v_app.scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            CASE WHEN p_reason IS NOT NULL AND btrim(p_reason) <> '' THEN ': ' || p_reason ELSE '' END
        ),
        v_ctx.actor_name
    );

    RETURN jsonb_build_object('success', true, 'appointment_id', p_appointment_id);
END;
$function$;

COMMIT;
