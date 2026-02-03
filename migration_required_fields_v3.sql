CREATE OR REPLACE FUNCTION public.validate_ticket_requirements()
RETURNS trigger AS $$
DECLARE
    workspace_config jsonb;
    req_fields jsonb;
    is_custom_enabled boolean;
    missing_fields text[] := ARRAY[]::text[];
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

        -- Loop checks based on config
        IF (req_fields->>'client_name')::boolean IS TRUE THEN
            IF NEW.client_name IS NULL OR trim(NEW.client_name) = '' THEN missing_fields := array_append(missing_fields, 'Cliente'); END IF;
        END IF;
        IF (req_fields->>'contact_info')::boolean IS TRUE THEN
            IF NEW.contact_info IS NULL OR trim(NEW.contact_info) = '' THEN missing_fields := array_append(missing_fields, 'Contato'); END IF;
        END IF;
        IF (req_fields->>'os_number')::boolean IS TRUE THEN
            IF NEW.os_number IS NULL OR trim(NEW.os_number) = '' THEN missing_fields := array_append(missing_fields, 'Nº OS'); END IF;
        END IF;
        IF (req_fields->>'serial_number')::boolean IS TRUE THEN
            IF NEW.serial_number IS NULL OR trim(NEW.serial_number) = '' THEN missing_fields := array_append(missing_fields, 'Nº Série / IMEI'); END IF;
        END IF;
        IF (req_fields->>'priority')::boolean IS TRUE THEN
            IF NEW.priority IS NULL OR trim(NEW.priority) = '' THEN missing_fields := array_append(missing_fields, 'Prioridade'); END IF;
        END IF;
        IF (req_fields->>'device_model')::boolean IS TRUE THEN
            IF NEW.device_model IS NULL OR trim(NEW.device_model) = '' THEN missing_fields := array_append(missing_fields, 'Modelo'); END IF;
        END IF;
        IF (req_fields->>'analysis_deadline')::boolean IS TRUE THEN
            IF NEW.analysis_deadline IS NULL THEN missing_fields := array_append(missing_fields, 'Prazo de Análise'); END IF;
        END IF;
        IF (req_fields->>'deadline')::boolean IS TRUE THEN
            IF NEW.deadline IS NULL THEN missing_fields := array_append(missing_fields, 'Prazo de Entrega'); END IF;
        END IF;
        IF (req_fields->>'device_condition')::boolean IS TRUE THEN
            IF NEW.device_condition IS NULL OR trim(NEW.device_condition) = '' THEN missing_fields := array_append(missing_fields, 'Situação do Aparelho'); END IF;
        END IF;
        IF (req_fields->>'defect_reported')::boolean IS TRUE THEN
            IF NEW.defect_reported IS NULL OR trim(NEW.defect_reported) = '' THEN missing_fields := array_append(missing_fields, 'Defeito Relatado'); END IF;
        END IF;
        IF (req_fields->>'responsible')::boolean IS TRUE THEN
            IF NEW.is_outsourced IS TRUE THEN
                IF NEW.outsourced_company_id IS NULL THEN missing_fields := array_append(missing_fields, 'Empresa Parceira'); END IF;
            ELSE
                IF NEW.technician_id IS NULL THEN missing_fields := array_append(missing_fields, 'Técnico Responsável'); END IF;
            END IF;
        END IF;
        IF (req_fields->>'checklist_entry')::boolean IS TRUE THEN
            IF NEW.checklist_data IS NULL OR jsonb_array_length(NEW.checklist_data) = 0 THEN missing_fields := array_append(missing_fields, 'Checklist de Entrada'); END IF;
        END IF;
        IF (req_fields->>'checklist_exit')::boolean IS TRUE THEN
            IF NEW.checklist_final_data IS NULL OR jsonb_array_length(NEW.checklist_final_data) = 0 THEN missing_fields := array_append(missing_fields, 'Checklist de Saída'); END IF;
        END IF;
        IF (req_fields->>'photos')::boolean IS TRUE THEN
            IF NEW.photos_urls IS NULL OR jsonb_array_length(NEW.photos_urls) = 0 THEN missing_fields := array_append(missing_fields, 'Fotos'); END IF;
        END IF;

    ELSE
        -- === STANDARD MODE (Default) ===
        -- Enforce: Client, OS, Model, Defect, Responsible, Analysis Deadline, Delivery Deadline

        IF NEW.client_name IS NULL OR trim(NEW.client_name) = '' THEN missing_fields := array_append(missing_fields, 'Cliente'); END IF;
        IF NEW.os_number IS NULL OR trim(NEW.os_number) = '' THEN missing_fields := array_append(missing_fields, 'Nº OS'); END IF;
        IF NEW.device_model IS NULL OR trim(NEW.device_model) = '' THEN missing_fields := array_append(missing_fields, 'Modelo'); END IF;
        IF NEW.defect_reported IS NULL OR trim(NEW.defect_reported) = '' THEN missing_fields := array_append(missing_fields, 'Defeito Relatado'); END IF;

        -- Responsible (Standard Legacy allow NULL technician if internal? No, typically 'responsible' implies someone is set,
        -- but legacy frontend logic allowed 'Todos' -> NULL.
        -- HOWEVER, the new instruction implies tightening defaults.
        -- "Standard Mode" usually means "What was before".
        -- Before, 'Responsible' was checked in frontend: "if (!this.ticketForm.technician_id) return notify..."
        -- BUT 'all' was valid. 'all' -> NULL.
        -- So for Standard Mode, we should probably ALLOW NULL technician (Todos) to be consistent with legacy.
        -- BUT for Outsourced, Company is strictly required.
        IF NEW.is_outsourced IS TRUE AND NEW.outsourced_company_id IS NULL THEN
            missing_fields := array_append(missing_fields, 'Empresa Parceira');
        END IF;
        -- Note: We do NOT enforce technician_id IS NOT NULL here to keep legacy 'Todos' support in standard mode.

        -- NEW MANDATORY DEFAULTS
        IF NEW.analysis_deadline IS NULL THEN missing_fields := array_append(missing_fields, 'Prazo de Análise'); END IF;
        IF NEW.deadline IS NULL THEN missing_fields := array_append(missing_fields, 'Prazo de Entrega'); END IF;

    END IF;

    -- 3. Raise Exception
    IF array_length(missing_fields, 1) > 0 THEN
        RAISE EXCEPTION 'Campos obrigatórios não preenchidos: %', array_to_string(missing_fields, ', ');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
