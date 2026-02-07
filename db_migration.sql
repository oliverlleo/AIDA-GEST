-- 1. Add Column to tickets table (Idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'analysis_started_at') THEN
        ALTER TABLE tickets ADD COLUMN analysis_started_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;
    END IF;
END $$;

-- 2. Create RPC Function (Updated with Bold Tags)
CREATE OR REPLACE FUNCTION start_ticket_analysis(p_ticket_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_ticket RECORD;
    v_user_name TEXT;
    v_user_id UUID;
    v_token TEXT;
BEGIN
    -- Resolve Actor
    v_user_id := auth.uid();

    IF v_user_id IS NOT NULL AND v_user_id != '00000000-0000-0000-0000-000000000000'::UUID THEN
        v_user_name := 'Administrador';
    ELSE
        BEGIN
            v_token := current_setting('request.headers', true)::json->>'x-employee-token';
        EXCEPTION WHEN OTHERS THEN
            v_token := NULL;
        END;

        IF v_token IS NOT NULL THEN
            v_user_name := 'Técnico';
        ELSE
            v_user_name := 'Sistema';
        END IF;
    END IF;

    -- 1. Fetch Ticket
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

    -- 4. Insert Log (With BOLD formatting)
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
        format('ANÁLISE DO <b>%s</b> DE <b>%s</b> da OS <b>%s</b> FOI INICIADA', UPPER(v_ticket.device_model), UPPER(v_ticket.client_name), v_ticket.os_number),
        v_user_name,
        NOW()
    );
END;
$$;

-- Permissions
REVOKE ALL ON FUNCTION start_ticket_analysis(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION start_ticket_analysis(UUID) TO authenticated;

-- 3. Reload Schema Cache
NOTIFY pgrst, 'reload schema';
