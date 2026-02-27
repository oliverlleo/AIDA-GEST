-- 1. Add analysis_started_at column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'analysis_started_at') THEN
        ALTER TABLE tickets ADD COLUMN analysis_started_at timestamp with time zone;
    END IF;
END $$;

DROP FUNCTION IF EXISTS start_ticket_analysis(uuid);

-- 2. Create RPC to start analysis securely
CREATE OR REPLACE FUNCTION start_ticket_analysis(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_ticket tickets%ROWTYPE;
    v_log_message text;
    v_user_name text;
BEGIN
    -- Check RLS visibility immediately by trying to SELECT
    SELECT * INTO v_ticket FROM tickets WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chamado não encontrado ou acesso negado.';
    END IF;

    -- Update the ticket
    -- This will fail if RLS for UPDATE prevents it, which is desired.
    UPDATE tickets
    SET analysis_started_at = now()
    WHERE id = p_ticket_id
      AND status = 'Analise Tecnica'
      AND analysis_started_at IS NULL
    RETURNING * INTO v_ticket;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Não foi possível iniciar a análise. O chamado pode não estar na fase correta ou já ter sido iniciado.';
    END IF;

    -- Construct Log Message
    v_log_message := format(
        'ANÁLISE DO %s DE %s da OS %s FOI INICIADA',
        UPPER(COALESCE(v_ticket.device_model, 'APARELHO')),
        UPPER(COALESCE(v_ticket.client_name, 'CLIENTE')),
        COALESCE(v_ticket.os_number, '?')
    );

    -- Try to get user name from claims if possible, or fallback
    -- Note: current_setting might be empty if not set by middleware, defaulting to 'Sistema' or 'Técnico'
    BEGIN
        v_user_name := current_setting('request.jwt.claim.name', true);
    EXCEPTION WHEN OTHERS THEN
        v_user_name := NULL;
    END;

    IF v_user_name IS NULL OR v_user_name = '' THEN
        v_user_name := 'Técnico';
    END IF;

    -- Insert into History/Logs
    INSERT INTO ticket_logs (ticket_id, action, details, user_name, workspace_id)
    VALUES (
        p_ticket_id,
        'Iniciou Análise',
        v_log_message,
        v_user_name,
        v_ticket.workspace_id
    );

    RETURN to_jsonb(v_ticket);
END;
$$;

GRANT EXECUTE ON FUNCTION start_ticket_analysis(uuid) TO anon, authenticated, service_role;
