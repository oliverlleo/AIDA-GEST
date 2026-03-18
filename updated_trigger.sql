
CREATE OR REPLACE FUNCTION public.validate_ticket_requirements()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    workspace_config jsonb;
    req_fields jsonb;
    is_custom_enabled boolean;
    missing_fields text[] := ARRAY[]::text[];

    -- Helper to check if a field is "missing" (NULL or empty string/array)
    v_new_missing boolean;
    v_old_missing boolean;
BEGIN
    -- 1. Fetch Config
    SELECT tracker_config INTO workspace_config
    FROM public.workspaces
    WHERE id = NEW.workspace_id;

    -- Determine Mode
    is_custom_enabled := (workspace_config->>'enable_required_ticket_fields')::boolean;

    IF is_custom_enabled IS TRUE THEN
        -- === CUSTOM MODE ===
        req_fields := workspace_config->'required_ticket_fields';

        -- CLIENT NAME
        IF (req_fields->>'client_name')::boolean IS TRUE THEN
            v_new_missing := (NEW.client_name IS NULL OR trim(NEW.client_name) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Cliente');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.client_name IS NULL OR trim(OLD.client_name) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Cliente'); END IF;
                END IF;
            END IF;
        END IF;

        -- CONTACT INFO
        IF (req_fields->>'contact_info')::boolean IS TRUE THEN
            v_new_missing := (NEW.contact_info IS NULL OR trim(NEW.contact_info) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Contato');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.contact_info IS NULL OR trim(OLD.contact_info) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Contato'); END IF;
                END IF;
            END IF;
        END IF;

        -- OS NUMBER
        IF (req_fields->>'os_number')::boolean IS TRUE THEN
            v_new_missing := (NEW.os_number IS NULL OR trim(NEW.os_number) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Nº OS');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.os_number IS NULL OR trim(OLD.os_number) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Nº OS'); END IF;
                END IF;
            END IF;
        END IF;

        -- SERIAL NUMBER
        IF (req_fields->>'serial_number')::boolean IS TRUE THEN
            v_new_missing := (NEW.serial_number IS NULL OR trim(NEW.serial_number) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Nº Série / IMEI');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.serial_number IS NULL OR trim(OLD.serial_number) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Nº Série / IMEI'); END IF;
                END IF;
            END IF;
        END IF;

        -- PRIORITY
        IF (req_fields->>'priority')::boolean IS TRUE THEN
            v_new_missing := (NEW.priority IS NULL OR trim(NEW.priority) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Prioridade');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.priority IS NULL OR trim(OLD.priority) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Prioridade'); END IF;
                END IF;
            END IF;
        END IF;

        -- DEVICE MODEL
        IF (req_fields->>'device_model')::boolean IS TRUE THEN
            v_new_missing := (NEW.device_model IS NULL OR trim(NEW.device_model) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Modelo');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.device_model IS NULL OR trim(OLD.device_model) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Modelo'); END IF;
                END IF;
            END IF;
        END IF;

        -- ANALYSIS DEADLINE
        IF (req_fields->>'analysis_deadline')::boolean IS TRUE THEN
            v_new_missing := (NEW.analysis_deadline IS NULL);
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Prazo de Análise');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.analysis_deadline IS NULL);
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Prazo de Análise'); END IF;
                END IF;
            END IF;
        END IF;

        -- DEADLINE (DELIVERY)
        IF (req_fields->>'deadline')::boolean IS TRUE THEN
            v_new_missing := (NEW.deadline IS NULL);
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Prazo de Entrega');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.deadline IS NULL);
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Prazo de Entrega'); END IF;
                END IF;
            END IF;
        END IF;

        -- DEVICE CONDITION
        IF (req_fields->>'device_condition')::boolean IS TRUE THEN
            v_new_missing := (NEW.device_condition IS NULL OR trim(NEW.device_condition) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Situação do Aparelho');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.device_condition IS NULL OR trim(OLD.device_condition) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Situação do Aparelho'); END IF;
                END IF;
            END IF;
        END IF;

        -- DEFECT REPORTED
        IF (req_fields->>'defect_reported')::boolean IS TRUE THEN
            v_new_missing := (NEW.defect_reported IS NULL OR trim(NEW.defect_reported) = '');
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Defeito Relatado');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.defect_reported IS NULL OR trim(OLD.defect_reported) = '');
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Defeito Relatado'); END IF;
                END IF;
            END IF;
        END IF;

        -- RESPONSIBLE (Technician or Outsourced Company)
        IF (req_fields->>'responsible')::boolean IS TRUE THEN
            IF NEW.is_outsourced IS TRUE THEN
                v_new_missing := (NEW.outsourced_company_id IS NULL);
                IF v_new_missing THEN
                    IF TG_OP = 'INSERT' THEN
                        missing_fields := array_append(missing_fields, 'Empresa Parceira');
                    ELSIF TG_OP = 'UPDATE' THEN
                        v_old_missing := (OLD.outsourced_company_id IS NULL);
                        IF NOT (v_old_missing AND OLD.is_outsourced IS TRUE) THEN
                             missing_fields := array_append(missing_fields, 'Empresa Parceira');
                        END IF;
                    END IF;
                END IF;
            ELSE
                v_new_missing := (NEW.technician_id IS NULL);
                IF v_new_missing THEN
                    IF TG_OP = 'INSERT' THEN
                        missing_fields := array_append(missing_fields, 'Técnico Responsável');
                    ELSIF TG_OP = 'UPDATE' THEN
                        v_old_missing := (OLD.technician_id IS NULL);
                        IF NOT (v_old_missing AND OLD.is_outsourced IS FALSE) THEN
                             missing_fields := array_append(missing_fields, 'Técnico Responsável');
                        END IF;
                    END IF;
                END IF;
            END IF;
        END IF;

        -- CHECKLIST ENTRY
        IF (req_fields->>'checklist_entry')::boolean IS TRUE THEN
            v_new_missing := (NEW.checklist_data IS NULL OR jsonb_array_length(NEW.checklist_data) = 0);
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Checklist de Entrada');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.checklist_data IS NULL OR jsonb_array_length(OLD.checklist_data) = 0);
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Checklist de Entrada'); END IF;
                END IF;
            END IF;
        END IF;

        -- CHECKLIST EXIT
        IF (req_fields->>'checklist_exit')::boolean IS TRUE THEN
            v_new_missing := (NEW.checklist_final_data IS NULL OR jsonb_array_length(NEW.checklist_final_data) = 0);
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Checklist de Saída');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.checklist_final_data IS NULL OR jsonb_array_length(OLD.checklist_final_data) = 0);
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Checklist de Saída'); END IF;
                END IF;
            END IF;
        END IF;

        -- PHOTOS
        IF (req_fields->>'photos')::boolean IS TRUE THEN
            v_new_missing := (NEW.photos_urls IS NULL OR jsonb_array_length(NEW.photos_urls) = 0);
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Fotos');
                ELSIF TG_OP = 'UPDATE' THEN
                    v_old_missing := (OLD.photos_urls IS NULL OR jsonb_array_length(OLD.photos_urls) = 0);
                    IF NOT v_old_missing THEN missing_fields := array_append(missing_fields, 'Fotos'); END IF;
                END IF;
            END IF;
        END IF;

    ELSE
        -- === STANDARD MODE (Legacy Default) ===

        -- Client
        v_new_missing := (NEW.client_name IS NULL OR trim(NEW.client_name) = '');
        IF v_new_missing THEN
            IF TG_OP = 'INSERT' THEN missing_fields := array_append(missing_fields, 'Cliente');
            ELSIF TG_OP = 'UPDATE' AND NOT (OLD.client_name IS NULL OR trim(OLD.client_name) = '') THEN missing_fields := array_append(missing_fields, 'Cliente'); END IF;
        END IF;

        -- OS Number
        v_new_missing := (NEW.os_number IS NULL OR trim(NEW.os_number) = '');
        IF v_new_missing THEN
            IF TG_OP = 'INSERT' THEN missing_fields := array_append(missing_fields, 'Nº OS');
            ELSIF TG_OP = 'UPDATE' AND NOT (OLD.os_number IS NULL OR trim(OLD.os_number) = '') THEN missing_fields := array_append(missing_fields, 'Nº OS'); END IF;
        END IF;

        -- Model
        v_new_missing := (NEW.device_model IS NULL OR trim(NEW.device_model) = '');
        IF v_new_missing THEN
            IF TG_OP = 'INSERT' THEN missing_fields := array_append(missing_fields, 'Modelo');
            ELSIF TG_OP = 'UPDATE' AND NOT (OLD.device_model IS NULL OR trim(OLD.device_model) = '') THEN missing_fields := array_append(missing_fields, 'Modelo'); END IF;
        END IF;

        -- Defect
        v_new_missing := (NEW.defect_reported IS NULL OR trim(NEW.defect_reported) = '');
        IF v_new_missing THEN
            IF TG_OP = 'INSERT' THEN missing_fields := array_append(missing_fields, 'Defeito Relatado');
            ELSIF TG_OP = 'UPDATE' AND NOT (OLD.defect_reported IS NULL OR trim(OLD.defect_reported) = '') THEN missing_fields := array_append(missing_fields, 'Defeito Relatado'); END IF;
        END IF;

        -- Outsourced Company (Strict if Outsourced)
        IF NEW.is_outsourced IS TRUE THEN
            v_new_missing := (NEW.outsourced_company_id IS NULL);
            IF v_new_missing THEN
                IF TG_OP = 'INSERT' THEN
                    missing_fields := array_append(missing_fields, 'Empresa Parceira');
                ELSIF TG_OP = 'UPDATE' THEN
                    IF NOT (OLD.outsourced_company_id IS NULL AND OLD.is_outsourced IS TRUE) THEN
                        missing_fields := array_append(missing_fields, 'Empresa Parceira');
                    END IF;
                END IF;
            END IF;
        END IF;

        -- Deadlines (New defaults)
        v_new_missing := (NEW.analysis_deadline IS NULL);
        IF v_new_missing THEN
            IF TG_OP = 'INSERT' THEN missing_fields := array_append(missing_fields, 'Prazo de Análise');
            ELSIF TG_OP = 'UPDATE' AND NOT (OLD.analysis_deadline IS NULL) THEN missing_fields := array_append(missing_fields, 'Prazo de Análise'); END IF;
        END IF;

        v_new_missing := (NEW.deadline IS NULL);
        IF v_new_missing THEN
            IF TG_OP = 'INSERT' THEN missing_fields := array_append(missing_fields, 'Prazo de Entrega');
            ELSIF TG_OP = 'UPDATE' AND NOT (OLD.deadline IS NULL) THEN missing_fields := array_append(missing_fields, 'Prazo de Entrega'); END IF;
        END IF;

    END IF;

    -- 3. Raise Exception
    IF array_length(missing_fields, 1) > 0 THEN
        RAISE EXCEPTION 'Campos obrigatórios não preenchidos: %', array_to_string(missing_fields, ', ');
    END IF;

    RETURN NEW;
END;
$function$
