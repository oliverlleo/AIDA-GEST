DROP FUNCTION IF EXISTS public.get_unscheduled_tickets(uuid, text, text, integer, integer);

CREATE OR REPLACE FUNCTION public.get_unscheduled_tickets(
    p_technician_id uuid DEFAULT NULL::uuid,
    p_appointment_type text DEFAULT NULL::text,
    p_status text DEFAULT NULL::text,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_ctx record;
    v_ws_id uuid;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    -- Validar técnico
    IF p_technician_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.employees WHERE id = p_technician_id AND workspace_id = v_ws_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Técnico não encontrado ou não pertence ao workspace.';
    END IF;

    RETURN (
        WITH tickets_query AS (
            SELECT t.id, t.os_number, t.client_name, t.status, t.technician_id, e.name AS technician_name, t.entry_date, t.device_model, t.priority, t.deadline
            FROM public.tickets t
            LEFT JOIN public.employees e ON e.id = t.technician_id
            WHERE t.workspace_id = v_ws_id
              AND t.deleted_at IS NULL
              AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
              AND (p_status IS NULL OR t.status = p_status)
              AND NOT EXISTS (
                  SELECT 1 FROM public.ticket_appointments a
                  WHERE a.ticket_id = t.id
                    AND a.deleted_at IS NULL
                    AND a.status != 'cancelled'
                    AND (p_appointment_type IS NULL OR a.appointment_type = p_appointment_type)
              )
            ORDER BY t.entry_date DESC
            LIMIT p_limit OFFSET p_offset
        ),
        total_count AS (
             SELECT COUNT(t.id) as ct
             FROM public.tickets t
             WHERE t.workspace_id = v_ws_id
              AND t.deleted_at IS NULL
              AND (p_technician_id IS NULL OR t.technician_id = p_technician_id)
              AND (p_status IS NULL OR t.status = p_status)
              AND NOT EXISTS (
                  SELECT 1 FROM public.ticket_appointments a
                  WHERE a.ticket_id = t.id
                    AND a.deleted_at IS NULL
                    AND a.status != 'cancelled'
                    AND (p_appointment_type IS NULL OR a.appointment_type = p_appointment_type)
              )
        )
        SELECT jsonb_build_object(
            'items', COALESCE((SELECT jsonb_agg(row_to_json(tickets_query)) FROM tickets_query), '[]'::jsonb),
            'total', (SELECT ct FROM total_count)
        )
    );
END;
$function$;
GRANT EXECUTE ON FUNCTION public.get_unscheduled_tickets TO authenticated;
