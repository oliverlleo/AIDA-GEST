-- Function to generate OS Number
CREATE OR REPLACE FUNCTION public.assign_ticket_os_number()
RETURNS trigger AS $$
DECLARE
    workspace_config jsonb;
    os_config jsonb;
    mode text;
    prefix text;
    start_seq int;
    length int;
    new_os text;
    exists_count int;
    max_retries int := 10;
    i int;
    is_unique boolean := false;
    current_seq int;
BEGIN
    -- 1. Fetch Config (SECURITY DEFINER allows reading config)
    SELECT tracker_config INTO workspace_config
    FROM public.workspaces
    WHERE id = NEW.workspace_id;

    -- If config is null, skip
    IF workspace_config IS NULL THEN
        RETURN NEW;
    END IF;

    os_config := workspace_config->'os_generation';

    -- If disabled or not present, skip
    IF os_config IS NULL OR (os_config->>'enabled')::boolean IS DISTINCT FROM true THEN
        RETURN NEW;
    END IF;

    -- 2. Configuration Parameters
    mode := COALESCE(os_config->>'mode', 'random');
    prefix := COALESCE(os_config->>'prefix', '');
    start_seq := COALESCE((os_config->>'start_seq')::int, 1000);
    length := COALESCE((os_config->>'length')::int, 6);

    -- 3. Generation Logic
    IF mode = 'sequential' THEN
        -- Locking: We need to update the sequence in the workspace row.
        -- We lock the workspace row FOR UPDATE to ensure sequential integrity.
        SELECT (tracker_config->'os_generation'->>'start_seq')::int
        INTO current_seq
        FROM public.workspaces
        WHERE id = NEW.workspace_id
        FOR UPDATE;

        current_seq := COALESCE(current_seq, start_seq);
        new_os := prefix || current_seq::text;

        -- Increment sequence in JSON
        UPDATE public.workspaces
        SET tracker_config = jsonb_set(
            tracker_config,
            '{os_generation, start_seq}',
            to_jsonb(current_seq + 1)
        )
        WHERE id = NEW.workspace_id;

    ELSIF mode = 'random' THEN
        -- Retry loop for uniqueness
        FOR i IN 1..max_retries LOOP
            -- Generate Random String (Upper case alphanumeric)
            -- We use md5(random) and take substring, then uppercase.
            -- Or floor(random) for numbers.
            -- Requirement: "nunca pode repetir numero se uma hora a quantidade de numero for insuficiente adicione o digito"
            -- Interpretation: Start with length N. If specific retries fail, maybe increase length?
            -- Implementation: Just generate alphanumeric string of 'length'.

            new_os := prefix || upper(substr(md5(random()::text), 1, length));

            -- Check Uniqueness in Workspace
            SELECT count(*) INTO exists_count
            FROM public.tickets
            WHERE workspace_id = NEW.workspace_id AND os_number = new_os;

            IF exists_count = 0 THEN
                is_unique := true;
                EXIT; -- Found unique
            END IF;
        END LOOP;

        -- Fallback: If still not unique after retries, try increasing length or appending timestamp
        IF NOT is_unique THEN
             new_os := prefix || upper(substr(md5(random()::text), 1, length + 2)); -- Emergency fallback
        END IF;
    END IF;

    -- 4. Set the Value
    IF new_os IS NOT NULL THEN
        NEW.os_number := new_os;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Trigger: Must run BEFORE validation.
-- Naming it '_assign_ticket_os_number' ensures alphabetical precedence over 'check_ticket_requirements' (if present).
-- Or 'assign...' vs 'check...'. 'a' < 'c'. Correct.

DROP TRIGGER IF EXISTS assign_ticket_os_number ON public.tickets;
CREATE TRIGGER assign_ticket_os_number
    BEFORE INSERT ON public.tickets
    FOR EACH ROW
    EXECUTE FUNCTION public.assign_ticket_os_number();
