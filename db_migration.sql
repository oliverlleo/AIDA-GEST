-- 1. Add Column to tickets table
-- We use a DO block to safely add the column only if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'analysis_started_at') THEN
        ALTER TABLE tickets ADD COLUMN analysis_started_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;
    END IF;
END $$;

-- 2. Create RPC Function
-- This function handles the "Start Analysis" action transactionally.
-- It uses SECURITY INVOKER to respect existing RLS policies (workspace isolation).
CREATE OR REPLACE FUNCTION start_ticket_analysis(p_ticket_id UUID, p_user_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER -- Respects RLS of the caller
SET search_path = public
AS $$
DECLARE
    v_ticket RECORD;
    v_updated_rows INT;
BEGIN
    -- 1. Fetch Ticket (RLS applies here)
    SELECT * INTO v_ticket
    FROM tickets
    WHERE id = p_ticket_id;

    -- 2. Validations
    IF v_ticket IS NULL THEN
        RAISE EXCEPTION 'Chamado não encontrado ou acesso negado (Workspace).';
    END IF;

    IF v_ticket.status != 'Analise Tecnica' THEN
        RAISE EXCEPTION 'O chamado deve estar em Análise Técnica para iniciar.';
    END IF;

    IF v_ticket.analysis_started_at IS NOT NULL THEN
        RAISE EXCEPTION 'A análise deste chamado já foi iniciada.';
    END IF;

    -- 3. Update Ticket
    UPDATE tickets
    SET
        analysis_started_at = NOW(),
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- 4. Insert Log
    -- Message Format: "ANÁLISE DO {MODELO} DE {CLIENTE} da OS {OS} FOI INICIADA"
    INSERT INTO ticket_logs (
        ticket_id,
        action,
        details,
        user_name,
        created_at
    )
    VALUES (
        p_ticket_id,
        'Iniciou Análise',
        format('ANÁLISE DO %s DE %s da OS %s FOI INICIADA', UPPER(v_ticket.device_model), UPPER(v_ticket.client_name), v_ticket.os_number),
        p_user_name,
        NOW()
    );

    -- 5. Insert Activity (Assuming unified log table or if there's a separate one, adapting.
    -- Based on code analysis, 'ticket_logs' seems to be the source for "Last Activities")

END;
$$;
