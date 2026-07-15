-- Pausa o reparo para compra adicional sem contabilizar o tempo de espera.
-- As RPCs validam workspace, papel e técnico antes de alterar a OS.

BEGIN;

ALTER TABLE public.tickets
    ADD COLUMN IF NOT EXISTS repair_elapsed_seconds integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS repair_paused_at timestamp with time zone,
    ADD COLUMN IF NOT EXISTS repair_resume_count integer NOT NULL DEFAULT 0;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'tickets_repair_elapsed_seconds_nonnegative'
          AND conrelid = 'public.tickets'::regclass
    ) THEN
        ALTER TABLE public.tickets
            ADD CONSTRAINT tickets_repair_elapsed_seconds_nonnegative
            CHECK (repair_elapsed_seconds >= 0);
    END IF;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.pause_repair_for_parts(
    p_ticket_id uuid,
    p_parts_needed text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket record;
    v_elapsed integer;
    v_parts text;
    v_elapsed_label text;
BEGIN
    v_parts := NULLIF(btrim(p_parts_needed), '');
    IF v_parts IS NULL THEN
        RAISE EXCEPTION 'Informe a peça ou componente necessário.';
    END IF;

    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id
      AND workspace_id = v_ctx.workspace_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'Somente reparos em andamento podem ser pausados para compra.';
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode pausar o próprio reparo.';
    END IF;

    IF v_ticket.repair_start_at IS NULL THEN
        RAISE EXCEPTION 'Inicie o reparo antes de pausá-lo para compra.';
    END IF;

    v_elapsed := COALESCE(v_ticket.repair_elapsed_seconds, 0)
        + GREATEST(0, EXTRACT(EPOCH FROM (now() - v_ticket.repair_start_at))::integer);
    v_elapsed_label := format(
        '%s:%s:%s',
        lpad((v_elapsed / 3600)::text, 2, '0'),
        lpad(((v_elapsed % 3600) / 60)::text, 2, '0'),
        lpad((v_elapsed % 60)::text, 2, '0')
    );

    UPDATE public.tickets
    SET status = 'Compra Peca',
        parts_needed = CASE
            WHEN NULLIF(btrim(COALESCE(parts_needed, '')), '') IS NULL THEN v_parts
            ELSE btrim(parts_needed) || E'\n' || v_parts
        END,
        parts_status = 'Pendente',
        repair_elapsed_seconds = v_elapsed,
        repair_paused_at = now(),
        repair_start_at = NULL,
        updated_at = now()
    WHERE id = v_ticket.id
      AND workspace_id = v_ctx.workspace_id;

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        v_ticket.id,
        'Pausou Reparo para Compra',
        format(
            'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi pausado por **%s** para comprar **%s**. Tempo contabilizado: **%s**.',
            COALESCE(v_ticket.os_number, 'não informada'),
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name,
            v_parts,
            v_elapsed_label
        ),
        v_ctx.actor_name
    );

    RETURN jsonb_build_object('success', true, 'elapsed_seconds', v_elapsed);
END;
$function$;

CREATE OR REPLACE FUNCTION public.resume_repair_after_parts(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket record;
    v_elapsed_label text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id
      AND workspace_id = v_ctx.workspace_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND
       OR v_ticket.status <> 'Compra Peca'
       OR v_ticket.repair_paused_at IS NULL THEN
        RAISE EXCEPTION 'Esta OS não está com um reparo pausado aguardando compra.';
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode retomar o próprio reparo.';
    END IF;

    v_elapsed_label := format(
        '%s:%s:%s',
        lpad((COALESCE(v_ticket.repair_elapsed_seconds, 0) / 3600)::text, 2, '0'),
        lpad(((COALESCE(v_ticket.repair_elapsed_seconds, 0) % 3600) / 60)::text, 2, '0'),
        lpad((COALESCE(v_ticket.repair_elapsed_seconds, 0) % 60)::text, 2, '0')
    );

    UPDATE public.tickets
    SET status = 'Andamento Reparo',
        parts_status = 'Recebido',
        parts_received_at = now(),
        repair_paused_at = NULL,
        repair_start_at = now(),
        repair_resume_count = COALESCE(repair_resume_count, 0) + 1,
        updated_at = now()
    WHERE id = v_ticket.id
      AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
    SET status = 'in_progress',
        actual_start = COALESCE(actual_start, now()),
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = now()
    WHERE id = (
        SELECT a.id
        FROM public.ticket_appointments AS a
        WHERE a.workspace_id = v_ctx.workspace_id
          AND a.ticket_id = v_ticket.id
          AND a.appointment_type = 'repair'
          AND a.status = 'scheduled'
          AND a.deleted_at IS NULL
        ORDER BY a.created_at DESC
        LIMIT 1
    );

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        v_ticket.id,
        'Retomou Reparo após Compra',
        format(
            'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi retomado por **%s** após a compra das peças. Tempo já contabilizado: **%s**. Novo ciclo iniciado.',
            COALESCE(v_ticket.os_number, 'não informada'),
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name,
            v_elapsed_label
        ),
        v_ctx.actor_name
    );

    RETURN jsonb_build_object('success', true, 'elapsed_seconds', COALESCE(v_ticket.repair_elapsed_seconds, 0));
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
    v_ticket record;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id
      AND workspace_id = v_ctx.workspace_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'A OS não está disponível para iniciar reparo.';
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode iniciar o próprio reparo.';
    END IF;

    IF v_ticket.repair_start_at IS NOT NULL THEN
        RAISE EXCEPTION 'O reparo já está em andamento.';
    END IF;

    UPDATE public.tickets
    SET repair_start_at = now(),
        repair_paused_at = NULL,
        updated_at = now()
    WHERE id = v_ticket.id
      AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
    SET status = 'in_progress',
        actual_start = COALESCE(actual_start, now()),
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = now()
    WHERE id = (
        SELECT a.id
        FROM public.ticket_appointments AS a
        WHERE a.workspace_id = v_ctx.workspace_id
          AND a.ticket_id = v_ticket.id
          AND a.appointment_type = 'repair'
          AND a.status = 'scheduled'
          AND a.deleted_at IS NULL
        ORDER BY a.created_at DESC
        LIMIT 1
    );

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        v_ticket.id,
        'Iniciou Execução',
        format(
            'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — iniciado por **%s**.',
            COALESCE(v_ticket.os_number, 'não informada'),
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name
        ),
        v_ctx.actor_name
    );

    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_repair_with_timer(
    p_ticket_id uuid,
    p_success boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket record;
    v_elapsed integer;
    v_next_status text;
    v_elapsed_label text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id
      AND workspace_id = v_ctx.workspace_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'A OS não está disponível para finalizar reparo.';
    END IF;

    IF v_ctx.actor_kind = 'employee'
       AND NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode finalizar o próprio reparo.';
    END IF;

    v_elapsed := COALESCE(v_ticket.repair_elapsed_seconds, 0)
        + CASE
            WHEN v_ticket.repair_start_at IS NULL THEN 0
            ELSE GREATEST(0, EXTRACT(EPOCH FROM (now() - v_ticket.repair_start_at))::integer)
          END;
    v_next_status := CASE WHEN p_success THEN 'Teste Final' ELSE 'Retirada Cliente' END;
    v_elapsed_label := format(
        '%s:%s:%s',
        lpad((v_elapsed / 3600)::text, 2, '0'),
        lpad(((v_elapsed % 3600) / 60)::text, 2, '0'),
        lpad((v_elapsed % 60)::text, 2, '0')
    );

    UPDATE public.tickets
    SET status = v_next_status,
        repair_successful = p_success,
        repair_elapsed_seconds = v_elapsed,
        repair_end_at = now(),
        repair_start_at = NULL,
        repair_paused_at = NULL,
        updated_at = now()
    WHERE id = v_ticket.id
      AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
    SET status = 'completed',
        actual_start = COALESCE(actual_start, now()),
        actual_end = now(),
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = now()
    WHERE id = (
        SELECT a.id
        FROM public.ticket_appointments AS a
        WHERE a.workspace_id = v_ctx.workspace_id
          AND a.ticket_id = v_ticket.id
          AND a.appointment_type = 'repair'
          AND a.status IN ('scheduled', 'in_progress')
          AND a.deleted_at IS NULL
        ORDER BY a.created_at DESC
        LIMIT 1
    );

    INSERT INTO public.ticket_logs (ticket_id, action, details, user_name)
    VALUES (
        v_ticket.id,
        'Finalizou Reparo',
        format(
            'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi finalizado por **%s** com resultado **%s**. Tempo total de execução: **%s**.',
            COALESCE(v_ticket.os_number, 'não informada'),
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name,
            CASE WHEN p_success THEN 'sucesso' ELSE 'sem reparo' END,
            v_elapsed_label
        ),
        v_ctx.actor_name
    );

    RETURN jsonb_build_object('success', true, 'elapsed_seconds', v_elapsed, 'status', v_next_status);
END;
$function$;

COMMIT;
