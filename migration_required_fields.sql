-- Function to validate required fields based on workspace config
CREATE OR REPLACE FUNCTION public.validate_ticket_requirements()
RETURNS trigger AS $$
DECLARE
    workspace_config jsonb;
    req_fields jsonb;
    missing_fields text[] := ARRAY[]::text[];
BEGIN
    -- 1. Fetch Config
    -- Using SECURITY DEFINER allows this to read workspace config even if RLS might restrict it in some contexts,
    -- though normally users have read access to their workspace.
    SELECT tracker_config INTO workspace_config
    FROM public.workspaces
    WHERE id = NEW.workspace_id;

    -- If no config or disabled, skip
    IF workspace_config IS NULL OR
       (workspace_config->>'enable_required_ticket_fields')::boolean IS DISTINCT FROM true THEN
        RETURN NEW;
    END IF;

    req_fields := workspace_config->'required_ticket_fields';

    -- 2. Validate Fields based on Configuration

    -- Client Name
    IF (req_fields->>'client_name')::boolean IS TRUE THEN
        IF NEW.client_name IS NULL OR trim(NEW.client_name) = '' THEN
            missing_fields := array_append(missing_fields, 'Cliente');
        END IF;
    END IF;

    -- Contact Info
    IF (req_fields->>'contact_info')::boolean IS TRUE THEN
        IF NEW.contact_info IS NULL OR trim(NEW.contact_info) = '' THEN
            missing_fields := array_append(missing_fields, 'Contato');
        END IF;
    END IF;

    -- OS Number
    IF (req_fields->>'os_number')::boolean IS TRUE THEN
        IF NEW.os_number IS NULL OR trim(NEW.os_number) = '' THEN
            missing_fields := array_append(missing_fields, 'Nº OS');
        END IF;
    END IF;

    -- Priority
    IF (req_fields->>'priority')::boolean IS TRUE THEN
        IF NEW.priority IS NULL OR trim(NEW.priority) = '' THEN
            missing_fields := array_append(missing_fields, 'Prioridade');
        END IF;
    END IF;

    -- Device Model
    IF (req_fields->>'device_model')::boolean IS TRUE THEN
        IF NEW.device_model IS NULL OR trim(NEW.device_model) = '' THEN
            missing_fields := array_append(missing_fields, 'Modelo');
        END IF;
    END IF;

    -- Analysis Deadline
    IF (req_fields->>'analysis_deadline')::boolean IS TRUE THEN
        IF NEW.analysis_deadline IS NULL THEN
            missing_fields := array_append(missing_fields, 'Prazo de Análise');
        END IF;
    END IF;

    -- Delivery Deadline
    IF (req_fields->>'deadline')::boolean IS TRUE THEN
        IF NEW.deadline IS NULL THEN
            missing_fields := array_append(missing_fields, 'Prazo de Entrega');
        END IF;
    END IF;

    -- Device Condition
    IF (req_fields->>'device_condition')::boolean IS TRUE THEN
        IF NEW.device_condition IS NULL OR trim(NEW.device_condition) = '' THEN
            missing_fields := array_append(missing_fields, 'Situação do Aparelho');
        END IF;
    END IF;

    -- Defect Reported
    IF (req_fields->>'defect_reported')::boolean IS TRUE THEN
        IF NEW.defect_reported IS NULL OR trim(NEW.defect_reported) = '' THEN
            missing_fields := array_append(missing_fields, 'Defeito Relatado');
        END IF;
    END IF;

    -- Responsible (Logic depends on is_outsourced)
    IF (req_fields->>'responsible')::boolean IS TRUE THEN
        IF NEW.is_outsourced IS TRUE THEN
            -- If Outsourced, Company ID is required
            IF NEW.outsourced_company_id IS NULL THEN
                missing_fields := array_append(missing_fields, 'Empresa Parceira');
            END IF;
        ELSE
            -- If Internal, Technician ID is required (No 'Todos'/NULL allowed)
            IF NEW.technician_id IS NULL THEN
                missing_fields := array_append(missing_fields, 'Técnico Responsável');
            END IF;
        END IF;
    END IF;

    -- Checklist Entry (JSONB Array)
    IF (req_fields->>'checklist_entry')::boolean IS TRUE THEN
        IF NEW.checklist_data IS NULL OR jsonb_array_length(NEW.checklist_data) = 0 THEN
            missing_fields := array_append(missing_fields, 'Checklist de Entrada');
        END IF;
    END IF;

    -- Checklist Exit (JSONB Array)
    IF (req_fields->>'checklist_exit')::boolean IS TRUE THEN
        IF NEW.checklist_final_data IS NULL OR jsonb_array_length(NEW.checklist_final_data) = 0 THEN
            missing_fields := array_append(missing_fields, 'Checklist de Saída');
        END IF;
    END IF;

    -- Photos (JSONB Array)
    IF (req_fields->>'photos')::boolean IS TRUE THEN
        IF NEW.photos_urls IS NULL OR jsonb_array_length(NEW.photos_urls) = 0 THEN
            missing_fields := array_append(missing_fields, 'Fotos');
        END IF;
    END IF;

    -- 3. Raise Exception if any check failed
    IF array_length(missing_fields, 1) > 0 THEN
        RAISE EXCEPTION 'Campos obrigatórios não preenchidos: %', array_to_string(missing_fields, ', ');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Trigger
DROP TRIGGER IF EXISTS check_ticket_requirements ON public.tickets;
CREATE TRIGGER check_ticket_requirements
    BEFORE INSERT OR UPDATE ON public.tickets
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_ticket_requirements();
