-- Corrige a sincronização entre a agenda real (ticket_appointments)
-- e os campos-resumo exibidos nos cards e no modal da OS.
--
-- Prazos (analysis_deadline/deadline) não fazem parte desta migração.

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_ticket_schedule_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ticket_id uuid;
    v_previous_ticket_id uuid;
BEGIN
    v_ticket_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.ticket_id ELSE NEW.ticket_id END;
    v_previous_ticket_id := CASE WHEN TG_OP = 'UPDATE' THEN OLD.ticket_id ELSE NULL END;

    -- O agendamento continua existindo durante todo o seu ciclo de vida.
    -- Somente cancelamento ou exclusão lógica remove o resumo da OS.
    UPDATE public.tickets AS t
    SET
        analysis_scheduled = EXISTS (
            SELECT 1
            FROM public.ticket_appointments AS a
            WHERE a.ticket_id = v_ticket_id
              AND a.appointment_type = 'analysis'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
        ),
        analysis_scheduled_at = (
            SELECT a.scheduled_start
            FROM public.ticket_appointments AS a
            WHERE a.ticket_id = v_ticket_id
              AND a.appointment_type = 'analysis'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
            ORDER BY a.created_at DESC
            LIMIT 1
        ),
        repair_scheduled = EXISTS (
            SELECT 1
            FROM public.ticket_appointments AS a
            WHERE a.ticket_id = v_ticket_id
              AND a.appointment_type = 'repair'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
        ),
        repair_scheduled_at = (
            SELECT a.scheduled_start
            FROM public.ticket_appointments AS a
            WHERE a.ticket_id = v_ticket_id
              AND a.appointment_type = 'repair'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
            ORDER BY a.created_at DESC
            LIMIT 1
        )
    WHERE t.id = v_ticket_id;

    -- Mantém o ticket anterior correto caso um agendamento seja movido entre OSs.
    IF v_previous_ticket_id IS NOT NULL
       AND v_previous_ticket_id IS DISTINCT FROM v_ticket_id THEN
        UPDATE public.tickets AS t
        SET
            analysis_scheduled = EXISTS (
                SELECT 1
                FROM public.ticket_appointments AS a
                WHERE a.ticket_id = v_previous_ticket_id
                  AND a.appointment_type = 'analysis'
                  AND a.deleted_at IS NULL
                  AND a.status <> 'cancelled'
            ),
            analysis_scheduled_at = (
                SELECT a.scheduled_start
                FROM public.ticket_appointments AS a
                WHERE a.ticket_id = v_previous_ticket_id
                  AND a.appointment_type = 'analysis'
                  AND a.deleted_at IS NULL
                  AND a.status <> 'cancelled'
                ORDER BY a.created_at DESC
                LIMIT 1
            ),
            repair_scheduled = EXISTS (
                SELECT 1
                FROM public.ticket_appointments AS a
                WHERE a.ticket_id = v_previous_ticket_id
                  AND a.appointment_type = 'repair'
                  AND a.deleted_at IS NULL
                  AND a.status <> 'cancelled'
            ),
            repair_scheduled_at = (
                SELECT a.scheduled_start
                FROM public.ticket_appointments AS a
                WHERE a.ticket_id = v_previous_ticket_id
                  AND a.appointment_type = 'repair'
                  AND a.deleted_at IS NULL
                  AND a.status <> 'cancelled'
                ORDER BY a.created_at DESC
                LIMIT 1
            )
        WHERE t.id = v_previous_ticket_id;
    END IF;

    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_ticket_appointment(p_ticket_id uuid, p_type text)
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

CREATE OR REPLACE FUNCTION public.complete_ticket_appointment(p_ticket_id uuid, p_type text)
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

-- Reconcilia registros já afetados pelo comportamento anterior.
WITH schedule_state AS (
    SELECT
        t.id,
        EXISTS (
            SELECT 1 FROM public.ticket_appointments AS a
            WHERE a.ticket_id = t.id
              AND a.appointment_type = 'analysis'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
        ) AS has_analysis,
        (
            SELECT a.scheduled_start FROM public.ticket_appointments AS a
            WHERE a.ticket_id = t.id
              AND a.appointment_type = 'analysis'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
            ORDER BY a.created_at DESC
            LIMIT 1
        ) AS analysis_at,
        EXISTS (
            SELECT 1 FROM public.ticket_appointments AS a
            WHERE a.ticket_id = t.id
              AND a.appointment_type = 'repair'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
        ) AS has_repair,
        (
            SELECT a.scheduled_start FROM public.ticket_appointments AS a
            WHERE a.ticket_id = t.id
              AND a.appointment_type = 'repair'
              AND a.deleted_at IS NULL
              AND a.status <> 'cancelled'
            ORDER BY a.created_at DESC
            LIMIT 1
        ) AS repair_at
    FROM public.tickets AS t
)
UPDATE public.tickets AS t
SET
    analysis_scheduled = s.has_analysis,
    analysis_scheduled_at = s.analysis_at,
    repair_scheduled = s.has_repair,
    repair_scheduled_at = s.repair_at
FROM schedule_state AS s
WHERE t.id = s.id
  AND (
      t.analysis_scheduled IS DISTINCT FROM s.has_analysis
      OR t.analysis_scheduled_at IS DISTINCT FROM s.analysis_at
      OR t.repair_scheduled IS DISTINCT FROM s.has_repair
      OR t.repair_scheduled_at IS DISTINCT FROM s.repair_at
  );

COMMIT;
