-- Defensive authorization and response-scope audit. No business records are changed.
BEGIN;
DO $$ BEGIN
 IF md5(pg_get_functiondef('public.aida_enforce_ticket_actor_identity()'::regprocedure))<>'6fc402a3be97751168553c8bf1a73fca' THEN RAISE EXCEPTION 'Unexpected definition: aida_enforce_ticket_actor_identity'; END IF;
 IF md5(pg_get_functiondef('public.start_ticket_analysis(uuid)'::regprocedure))<>'4987a1ab82403c1368723cfee5061055' THEN RAISE EXCEPTION 'Unexpected definition: start_ticket_analysis'; END IF;
 IF md5(pg_get_functiondef('public.start_repair_timer(uuid)'::regprocedure))<>'9e74d77b2b727bdef64d0bdf1791cc94' THEN RAISE EXCEPTION 'Unexpected definition: start_repair_timer'; END IF;
 IF md5(pg_get_functiondef('public.complete_repair_with_timer(uuid,boolean)'::regprocedure))<>'ab5ac85f141d12b1ac55c3f727f47107' THEN RAISE EXCEPTION 'Unexpected definition: complete_repair_with_timer'; END IF;
 IF md5(pg_get_functiondef('public.pause_repair_for_parts(uuid,text)'::regprocedure))<>'7d5498110d98f8c586aadee85fbff8cc' THEN RAISE EXCEPTION 'Unexpected definition: pause_repair_for_parts'; END IF;
 IF md5(pg_get_functiondef('public.resume_repair_after_parts(uuid)'::regprocedure))<>'2e4704c1f7b3d8b1de4e756305a0a247' THEN RAISE EXCEPTION 'Unexpected definition: resume_repair_after_parts'; END IF;
 IF md5(pg_get_functiondef('public.get_technician_schedule(uuid,text,date)'::regprocedure))<>'f9d120eb7d2843e9923baf97d4ac440a' THEN RAISE EXCEPTION 'Unexpected definition: get_technician_schedule'; END IF;
 IF md5(pg_get_functiondef('public.get_client_ticket_details_public(uuid,uuid)'::regprocedure))<>'82c0e8af5f0dcc86721729faed580f4e' THEN RAISE EXCEPTION 'Unexpected definition: get_client_ticket_details_public'; END IF;
 IF md5(pg_get_functiondef('public.complete_warranty_analysis(uuid,boolean,text,boolean,text,text)'::regprocedure))<>'c060ff9c9a06411ff6068a32a2f072ae' THEN RAISE EXCEPTION 'Unexpected definition: complete_warranty_analysis'; END IF;
 IF md5(pg_get_functiondef('public.link_warranty_paid_ticket(uuid,uuid)'::regprocedure))<>'1c93cbaa37f4e7619aee4caa42d93af1' THEN RAISE EXCEPTION 'Unexpected definition: link_warranty_paid_ticket'; END IF;
 IF md5(pg_get_functiondef('public.complete_repair_with_inventory(uuid,boolean,jsonb)'::regprocedure))<>'2152823fe21afc69dc8d115038f42c62' THEN RAISE EXCEPTION 'Unexpected definition: complete_repair_with_inventory'; END IF;
 IF md5(pg_get_functiondef('public.complete_warranty_analysis_with_inventory(uuid,text,text)'::regprocedure))<>'5619ffdd0006d585f218500a44802468' THEN RAISE EXCEPTION 'Unexpected definition: complete_warranty_analysis_with_inventory'; END IF;
 IF md5(pg_get_functiondef('public.return_ticket_inventory(uuid,numeric,text)'::regprocedure))<>'00df0c96f84314d6945a984428f425c6' THEN RAISE EXCEPTION 'Unexpected definition: return_ticket_inventory'; END IF;
 IF md5(pg_get_functiondef('public.get_ticket_appointments(uuid)'::regprocedure))<>'750cb7bd1567a0c8f3f862dbc750de37' THEN RAISE EXCEPTION 'Unexpected definition: get_ticket_appointments'; END IF;
 IF md5(pg_get_functiondef('public.create_ticket_appointment(uuid,uuid,text,timestamp with time zone,timestamp with time zone,text)'::regprocedure))<>'c0f61487c960c5a40a6c98c568c90abe' THEN RAISE EXCEPTION 'Unexpected definition: create_ticket_appointment'; END IF;
 IF md5(pg_get_functiondef('private.enforce_ticket_warranty()'::regprocedure))<>'c9af363651ea2abf2248e7503c542022' THEN RAISE EXCEPTION 'Unexpected definition: enforce_ticket_warranty'; END IF;
 IF md5(pg_get_functiondef('public.request_ticket_inventory_parts(uuid,jsonb,text,boolean)'::regprocedure))<>'ccb54d396ada46f6b80dfe344bdadf30' THEN RAISE EXCEPTION 'Unexpected definition: request_ticket_inventory_parts'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.aida_enforce_ticket_actor_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_can_technical boolean;
    v_can_test boolean;
    v_shared_work boolean;
    v_test_flow text;
BEGIN
    -- Operacoes internas e service_role continuam disponiveis para manutencao.
    IF COALESCE(auth.role(), '') NOT IN ('anon', 'authenticated') THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    IF TG_OP = 'INSERT' THEN
        NEW.workspace_id := v_ctx.workspace_id;
        NEW.created_by := COALESCE(v_ctx.actor_employee_id, v_ctx.actor_user_id);
        NEW.created_by_name := v_ctx.actor_name;

        IF NOT v_ctx.is_admin AND
           (NEW.analysis_started_at IS NOT NULL OR NEW.repair_start_at IS NOT NULL
            OR NEW.repair_end_at IS NOT NULL OR NEW.repair_paused_at IS NOT NULL
            OR NEW.repair_successful IS NOT NULL OR NEW.test_start_at IS NOT NULL
            OR COALESCE(NEW.repair_elapsed_seconds,0)<>0 OR COALESCE(NEW.repair_resume_count,0)<>0
            OR NEW.deleted_at IS NOT NULL) THEN
            RAISE EXCEPTION 'Acesso negado: abertura nao pode antecipar execucao tecnica ou exclusao.' USING ERRCODE='42501';
        END IF;
        IF NOT v_ctx.is_admin AND v_ctx.is_attendant
           AND COALESCE(NEW.status,'Aberto') NOT IN ('Aberto','Analise Tecnica')
           AND NOT (NEW.budget_status='Aprovado' AND NEW.status IN ('Compra Peca','Andamento Reparo')) THEN
            RAISE EXCEPTION 'Acesso negado: abertura exige fase inicial ou orcamento aprovado.' USING ERRCODE='42501';
        END IF;
        IF NOT v_ctx.is_admin AND NOT v_ctx.is_attendant THEN
            IF NOT v_ctx.is_technician OR NEW.technician_id IS DISTINCT FROM v_ctx.actor_employee_id
               OR COALESCE(NEW.status, 'Aberto') NOT IN ('Aberto', 'Analise Tecnica')
               OR COALESCE(NEW.budget_status, 'Pendente') <> 'Pendente'
               OR NEW.budget_value IS NOT NULL OR NEW.parts_purchased_at IS NOT NULL
               OR NEW.parts_received_at IS NOT NULL
               OR (NEW.supplier_purchases IS NOT NULL AND NEW.supplier_purchases <> '[]'::jsonb) THEN
                RAISE EXCEPTION 'Acesso negado: tecnico so pode criar seu chamado inicial sem aprovacao ou compra.' USING ERRCODE='42501';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    SELECT COALESCE(w.tracker_config->>'test_flow','kanban') INTO v_test_flow FROM public.workspaces w WHERE w.id=v_ctx.workspace_id;
    v_can_technical := v_ctx.is_admin OR (v_ctx.is_technician AND COALESCE(OLD.technician_id=v_ctx.actor_employee_id,false));
    v_shared_work := v_ctx.is_technician AND OLD.technician_id IS NULL AND OLD.status IN ('Analise Tecnica','Andamento Reparo','Teste Final');
    v_can_test := v_ctx.is_admin OR (CASE WHEN v_test_flow='tester' THEN 'tester'=ANY(COALESCE(v_ctx.actor_roles,'{}'::text[])) ELSE v_can_technical END);

    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.public_token IS DISTINCT FROM OLD.public_token
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_by_name IS DISTINCT FROM OLD.created_by_name THEN
        RAISE EXCEPTION 'Acesso negado: campos de identidade da OS nao podem ser alterados.';
    END IF;

    IF NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND NEW.technician_id IS DISTINCT FROM OLD.technician_id
       AND NOT (current_user NOT IN ('anon','authenticated') AND v_ctx.is_technician
                AND OLD.technician_id IS NULL AND NEW.technician_id=v_ctx.actor_employee_id
                AND OLD.status IN ('Analise Tecnica','Andamento Reparo','Teste Final')) THEN
        RAISE EXCEPTION 'Acesso negado: este cargo nao pode trocar o tecnico da OS.';
    END IF;


    IF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at AND NOT v_ctx.is_admin THEN
        RAISE EXCEPTION 'Acesso negado: somente administradores podem excluir ou restaurar chamados.' USING ERRCODE='42501';
    END IF;

    -- Direct REST writes are constrained by the operation's current role.
    -- Authorized SECURITY DEFINER workflows retain their derived inventory/warranty updates.
    -- This trigger must remain SECURITY INVOKER so current_user identifies direct requests.
    IF current_user IN ('anon','authenticated') AND NOT v_ctx.is_admin THEN
        IF NEW.analysis_started_at IS DISTINCT FROM OLD.analysis_started_at
           OR NEW.repair_start_at IS DISTINCT FROM OLD.repair_start_at
           OR NEW.repair_end_at IS DISTINCT FROM OLD.repair_end_at
           OR NEW.repair_elapsed_seconds IS DISTINCT FROM OLD.repair_elapsed_seconds
           OR NEW.repair_paused_at IS DISTINCT FROM OLD.repair_paused_at
           OR NEW.repair_resume_count IS DISTINCT FROM OLD.repair_resume_count
           OR (NEW.repair_successful IS DISTINCT FROM OLD.repair_successful
               AND NOT (v_ctx.is_attendant AND OLD.status='Aprovacao'
                        AND NEW.status='Retirada Cliente' AND NEW.budget_status='Negado' AND NEW.repair_successful=false)) THEN
            RAISE EXCEPTION 'Acesso negado: execucao tecnica exige a operacao autorizada do servidor.' USING ERRCODE='42501';
        END IF;
        IF OLD.status IN ('Andamento Reparo','Teste Final') AND NEW.status IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'Acesso negado: conclusao exige a operacao autorizada do servidor.' USING ERRCODE='42501';
        END IF;
        IF OLD.status='Analise Tecnica' AND NEW.status='Aprovacao' AND OLD.analysis_started_at IS NULL THEN
            RAISE EXCEPTION 'Inicie a analise antes de concluir.' USING ERRCODE='42501';
        END IF;
        IF 'tester'=ANY(COALESCE(v_ctx.actor_roles,'{}'::text[]))
           AND NOT v_ctx.is_attendant AND NOT v_can_technical AND NOT v_shared_work
           AND (to_jsonb(NEW)-ARRAY['test_start_at','test_notes','checklist_final_data','priority_requested','updated_at','overview_queue_stage','overview_queue_entered_at']::text[])
               IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['test_start_at','test_notes','checklist_final_data','priority_requested','updated_at','overview_queue_stage','overview_queue_entered_at']::text[]) THEN
            RAISE EXCEPTION 'Acesso negado: testador altera somente o teste e pedidos de prioridade.' USING ERRCODE='42501';
        END IF;
        IF OLD.status='Teste Final' AND NOT v_can_test AND
           (NEW.test_start_at IS DISTINCT FROM OLD.test_start_at
            OR NEW.test_notes IS DISTINCT FROM OLD.test_notes
            OR NEW.checklist_final_data IS DISTINCT FROM OLD.checklist_final_data) THEN
            RAISE EXCEPTION 'Acesso negado: este modo de teste exige outra permissao.' USING ERRCODE='42501';
        END IF;
        IF (v_can_technical OR v_shared_work) AND NOT v_ctx.is_attendant AND
           (to_jsonb(NEW) - ARRAY[
             'status','previous_status','tech_notes','parts_needed','parts_status',
             'checklist_data','checklist_final_data','photos_urls','deadline','analysis_deadline',
             'priority','priority_requested','analysis_started_at','repair_start_at','repair_end_at',
             'repair_successful','repair_elapsed_seconds','repair_paused_at','repair_resume_count',
             'test_start_at','test_notes','pickup_available','pickup_available_at','delivered_at',
             'delivery_method','carrier_name','tracking_code','outsourced_deadline',
             'outsourced_return_count','outsourced_notes','outsourced_at','updated_at',
             'overview_queue_stage','overview_queue_entered_at','is_outsourced','outsourced_company_id',
             'analysis_scheduled','repair_scheduled','analysis_scheduled_at','repair_scheduled_at'
           ]::text[]) IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY[
             'status','previous_status','tech_notes','parts_needed','parts_status',
             'checklist_data','checklist_final_data','photos_urls','deadline','analysis_deadline',
             'priority','priority_requested','analysis_started_at','repair_start_at','repair_end_at',
             'repair_successful','repair_elapsed_seconds','repair_paused_at','repair_resume_count',
             'test_start_at','test_notes','pickup_available','pickup_available_at','delivered_at',
             'delivery_method','carrier_name','tracking_code','outsourced_deadline',
             'outsourced_return_count','outsourced_notes','outsourced_at','updated_at',
             'overview_queue_stage','overview_queue_entered_at','is_outsourced','outsourced_company_id',
             'analysis_scheduled','repair_scheduled','analysis_scheduled_at','repair_scheduled_at'
           ]::text[]) THEN
            RAISE EXCEPTION 'Acesso negado: este cargo nao pode alterar cadastro, orcamento ou compra.' USING ERRCODE='42501';
        END IF;
        IF NOT v_ctx.is_attendant AND
           (NEW.is_outsourced IS DISTINCT FROM OLD.is_outsourced
            OR NEW.outsourced_company_id IS DISTINCT FROM OLD.outsourced_company_id)
           AND NOT (v_can_technical AND OLD.status='Aberto' AND NEW.status='Terceirizado'
                    AND NEW.is_outsourced AND NEW.outsourced_company_id IS NOT NULL) THEN
            RAISE EXCEPTION 'Acesso negado: parceiro so pode ser escolhido no envio autorizado.' USING ERRCODE='42501';
        END IF;
        IF v_ctx.is_technician AND NOT v_ctx.is_attendant
           AND NEW.parts_status IS DISTINCT FROM OLD.parts_status
           AND NOT (OLD.status='Analise Tecnica' AND NEW.status='Aprovacao'
                    AND COALESCE(NEW.parts_status,'N/A') IN ('Pendente','N/A')) THEN
            RAISE EXCEPTION 'Acesso negado: compra e recebimento de pecas exigem atendimento.' USING ERRCODE='42501';
        END IF;
        IF v_ctx.is_attendant AND NOT v_can_technical THEN
            IF NEW.analysis_started_at IS DISTINCT FROM OLD.analysis_started_at
               OR (NEW.repair_start_at IS DISTINCT FROM OLD.repair_start_at
                   AND NOT (v_can_test AND OLD.status='Teste Final' AND NEW.status='Andamento Reparo' AND NEW.repair_start_at IS NULL))
               OR NEW.repair_end_at IS DISTINCT FROM OLD.repair_end_at
               OR NEW.repair_elapsed_seconds IS DISTINCT FROM OLD.repair_elapsed_seconds
               OR NEW.repair_paused_at IS DISTINCT FROM OLD.repair_paused_at
               OR NEW.repair_resume_count IS DISTINCT FROM OLD.repair_resume_count
               OR (NEW.repair_successful IS DISTINCT FROM OLD.repair_successful
                   AND NOT (OLD.status='Aprovacao' AND NEW.budget_status='Negado' AND NEW.repair_successful=false)) THEN
                RAISE EXCEPTION 'Acesso negado: operacao tecnica exige permissao de tecnico.' USING ERRCODE='42501';
            END IF;
        END IF;
        IF NOT ('tester'=ANY(COALESCE(v_ctx.actor_roles,'{}'::text[]))) THEN
            IF NOT v_can_technical AND
               (NEW.test_start_at IS DISTINCT FROM OLD.test_start_at OR NEW.test_notes IS DISTINCT FROM OLD.test_notes) THEN
                RAISE EXCEPTION 'Acesso negado ao teste final.' USING ERRCODE='42501';
            END IF;
            IF v_ctx.is_technician AND OLD.status='Teste Final'
               AND EXISTS(SELECT 1 FROM public.workspaces w WHERE w.id=v_ctx.workspace_id AND w.tracker_config->>'test_flow'='tester')
               AND (NEW.status IS DISTINCT FROM OLD.status OR NEW.test_start_at IS DISTINCT FROM OLD.test_start_at
                    OR NEW.test_notes IS DISTINCT FROM OLD.test_notes OR NEW.checklist_final_data IS DISTINCT FROM OLD.checklist_final_data) THEN
                RAISE EXCEPTION 'Acesso negado: o teste final desta empresa exige testador.' USING ERRCODE='42501';
            END IF;
        END IF;
        IF NOT v_can_technical AND NEW.repair_start_at IS DISTINCT FROM OLD.repair_start_at
           AND NOT (v_can_test AND OLD.status='Teste Final' AND NEW.status='Andamento Reparo' AND NEW.repair_start_at IS NULL) THEN
            RAISE EXCEPTION 'Acesso negado: cronometro exige o tecnico responsavel.' USING ERRCODE='42501';
        END IF;
        IF v_shared_work AND NOT v_can_technical AND
           (NEW.analysis_started_at IS DISTINCT FROM OLD.analysis_started_at
            OR NEW.repair_end_at IS DISTINCT FROM OLD.repair_end_at
            OR NEW.repair_elapsed_seconds IS DISTINCT FROM OLD.repair_elapsed_seconds
            OR NEW.repair_successful IS DISTINCT FROM OLD.repair_successful
            OR NEW.repair_paused_at IS DISTINCT FROM OLD.repair_paused_at) THEN
            RAISE EXCEPTION 'Acesso negado: execucao tecnica exige atribuicao ao responsavel.' USING ERRCODE='42501';
        END IF;
        IF NEW.status IS DISTINCT FROM OLD.status THEN
            IF NOT (
                (OLD.status='Aberto' AND NEW.status IN ('Analise Tecnica','Terceirizado') AND (v_can_technical OR v_ctx.is_attendant))
                OR (OLD.status='Analise Tecnica' AND NEW.status='Aprovacao' AND v_can_technical)
                OR (OLD.status='Aprovacao' AND NEW.status IN ('Compra Peca','Andamento Reparo','Retirada Cliente') AND v_ctx.is_attendant)
                OR (OLD.status='Compra Peca' AND NEW.status='Andamento Reparo' AND v_ctx.is_attendant)
                OR (OLD.status='Andamento Reparo' AND NEW.status IN ('Teste Final','Retirada Cliente') AND v_can_technical)
                OR (OLD.status='Teste Final' AND NEW.status IN ('Retirada Cliente','Andamento Reparo','Terceirizado') AND v_can_test)
                OR (OLD.status='Terceirizado' AND NEW.status IN ('Teste Final','Retirada Cliente') AND (v_can_technical OR v_ctx.is_attendant))
                OR (OLD.status='Retirada Cliente' AND NEW.status='Finalizado' AND (v_can_technical OR v_ctx.is_attendant))
            ) THEN
                RAISE EXCEPTION 'Acesso negado: esta transicao exige outra permissao.' USING ERRCODE='42501';
            END IF;
        END IF;
    END IF;

    -- O testador atua apenas no resultado do teste. Dados cadastrais, fotos,
    -- pecas, tecnico e demais campos da OS permanecem fora de sua permissao.
    IF NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND NOT v_can_technical
       AND NOT v_shared_work
       AND 'tester' = ANY(COALESCE(v_ctx.actor_roles, '{}'::text[]))
       AND (
           to_jsonb(NEW) - ARRAY[
               'status', 'previous_status', 'test_start_at', 'test_notes', 'checklist_final_data', 'priority_requested',
               'deadline', 'priority', 'repair_start_at', 'updated_at',
               'outsourced_deadline', 'outsourced_return_count', 'outsourced_notes',
               'overview_queue_stage', 'overview_queue_entered_at'
           ]::text[]
       ) IS DISTINCT FROM (
           to_jsonb(OLD) - ARRAY[
               'status', 'previous_status', 'test_start_at', 'test_notes', 'checklist_final_data', 'priority_requested',
               'deadline', 'priority', 'repair_start_at', 'updated_at',
               'outsourced_deadline', 'outsourced_return_count', 'outsourced_notes',
               'overview_queue_stage', 'overview_queue_entered_at'
           ]::text[]
       ) THEN
        RAISE EXCEPTION 'Acesso negado: testador so pode registrar o andamento e o resultado do teste.';
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_ticket_analysis(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id
       AND t.workspace_id = v_ctx.workspace_id
       AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Analise Tecnica' OR v_ticket.analysis_started_at IS NOT NULL THEN
        RAISE EXCEPTION 'A OS não está disponível para iniciar análise.';
    END IF;

    IF NOT v_ctx.is_admin AND (NOT v_ctx.is_technician OR v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id) THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode iniciar a própria análise.';
    END IF;

    IF public.aida_config_bool(v_config, 'modules', 'agenda', true)
       AND public.aida_ticket_field_mode(v_config, 'analysis_schedule', false) = 'required'
       AND NOT EXISTS (
           SELECT 1 FROM public.ticket_appointments a
            WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
              AND a.appointment_type = 'analysis' AND a.status IN ('scheduled', 'in_progress')
              AND a.deleted_at IS NULL
       ) THEN
        RAISE EXCEPTION 'Agende a análise antes de iniciar o serviço.';
    END IF;

    UPDATE public.tickets
       SET analysis_started_at = now(), updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id
     RETURNING * INTO v_ticket;

    UPDATE public.ticket_appointments
       SET status = 'in_progress', actual_start = COALESCE(actual_start, now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'analysis' AND a.status = 'scheduled' AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Iniciou Análise', format(
        'A análise da OS **%s** — aparelho **%s** do cliente **%s** — foi iniciada por **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name), v_ctx.actor_name);

    RETURN to_jsonb(v_ticket);
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
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'A OS não está disponível para iniciar reparo.';
    END IF;
    IF NOT v_ctx.is_admin AND (NOT v_ctx.is_technician OR v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id) THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode iniciar o próprio reparo.';
    END IF;
    IF v_ticket.repair_start_at IS NOT NULL THEN
        RAISE EXCEPTION 'O reparo já está em andamento.';
    END IF;

    IF public.aida_config_bool(v_config, 'modules', 'agenda', true)
       AND public.aida_ticket_field_mode(v_config, 'repair_schedule', false) = 'required'
       AND NOT EXISTS (
           SELECT 1 FROM public.ticket_appointments a
            WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
              AND a.appointment_type = 'repair' AND a.status IN ('scheduled', 'in_progress')
              AND a.deleted_at IS NULL
       ) THEN
        RAISE EXCEPTION 'Agende o reparo antes de iniciar o serviço.';
    END IF;

    UPDATE public.tickets SET repair_start_at = now(), repair_paused_at = NULL, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
       SET status = 'in_progress', actual_start = COALESCE(actual_start, now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'repair' AND a.status = 'scheduled' AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Iniciou Execução', format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — iniciado por **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name), v_ctx.actor_name);
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_repair_with_timer(p_ticket_id uuid, p_success boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
    v_timer boolean;
    v_elapsed integer;
    v_next_status text;
    v_details text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'A OS não está disponível para finalizar reparo.';
    END IF;
    IF NOT v_ctx.is_admin AND (NOT v_ctx.is_technician OR v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id) THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode finalizar o próprio reparo.';
    END IF;

    IF p_success IS NULL THEN RAISE EXCEPTION 'Informe o resultado do reparo.' USING ERRCODE='22023'; END IF;
    IF v_ticket.repair_start_at IS NULL THEN RAISE EXCEPTION 'Inicie o reparo antes de concluir.' USING ERRCODE='42501'; END IF;
    IF public.aida_config_bool(v_config, 'modules', 'inventory', false) AND EXISTS(SELECT 1 FROM public.ticket_part_items tp WHERE tp.workspace_id=v_ctx.workspace_id AND tp.ticket_id=v_ticket.id AND tp.status NOT IN ('cancelled','released','consumed')) THEN
        RAISE EXCEPTION 'Conclua o reparo informando o uso das pecas reservadas.' USING ERRCODE='42501';
    END IF;
    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := CASE WHEN v_timer THEN COALESCE(v_ticket.repair_elapsed_seconds, 0)
        + CASE WHEN v_ticket.repair_start_at IS NULL THEN 0
               ELSE GREATEST(0, EXTRACT(EPOCH FROM (now() - v_ticket.repair_start_at))::integer) END
        ELSE 0 END;
    v_next_status := CASE WHEN p_success AND public.aida_config_bool(v_config, 'workflow', 'final_test', true)
                          THEN 'Teste Final' ELSE 'Retirada Cliente' END;

    UPDATE public.tickets
       SET status = v_next_status, repair_successful = p_success,
           repair_elapsed_seconds = v_elapsed, repair_end_at = now(), repair_start_at = NULL,
           repair_paused_at = NULL, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
       SET status = 'completed', actual_start = COALESCE(actual_start, now()), actual_end = now(),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'repair' AND a.status IN ('scheduled', 'in_progress') AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    v_details := format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi finalizado por **%s** com resultado **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name,
        CASE WHEN p_success THEN 'sucesso' ELSE 'sem reparo' END);
    IF v_timer THEN v_details := v_details || format(' Tempo total: **%s segundos**.', v_elapsed); END IF;
    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Finalizou Reparo', v_details, v_ctx.actor_name);
    RETURN jsonb_build_object('success', true, 'elapsed_seconds', v_elapsed, 'status', v_next_status);
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_repair_for_parts(p_ticket_id uuid, p_parts_needed text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
    v_parts text := NULLIF(btrim(p_parts_needed), '');
    v_timer boolean;
    v_elapsed integer;
    v_details text;
BEGIN
    IF v_parts IS NULL THEN RAISE EXCEPTION 'Informe a peça ou componente necessário.'; END IF;
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Andamento Reparo' THEN
        RAISE EXCEPTION 'Somente reparos em andamento podem ser pausados para compra.';
    END IF;
    IF NOT public.aida_config_bool(v_config, 'workflow', 'parts_control', true) THEN
        RAISE EXCEPTION 'O controle de compra de peças está desativado.';
    END IF;
    IF NOT v_ctx.is_admin AND (NOT v_ctx.is_technician OR v_ticket.technician_id IS DISTINCT FROM v_ctx.actor_employee_id) THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode pausar o próprio reparo.';
    END IF;
    IF v_ticket.repair_start_at IS NULL THEN RAISE EXCEPTION 'Inicie o reparo antes de pausá-lo para compra.'; END IF;

    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := CASE WHEN v_timer THEN COALESCE(v_ticket.repair_elapsed_seconds, 0)
        + GREATEST(0, EXTRACT(EPOCH FROM (now() - v_ticket.repair_start_at))::integer) ELSE 0 END;

    UPDATE public.tickets
       SET status = 'Compra Peca',
           parts_needed = CASE WHEN NULLIF(btrim(COALESCE(parts_needed, '')), '') IS NULL THEN v_parts
                               ELSE btrim(parts_needed) || E'\n' || v_parts END,
           parts_status = 'Pendente', repair_elapsed_seconds = v_elapsed,
           repair_paused_at = now(), repair_start_at = NULL, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    v_details := format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi pausado por **%s** para comprar **%s**.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name, v_parts);
    IF v_timer THEN v_details := v_details || format(' Tempo contabilizado: **%s segundos**.', v_elapsed); END IF;
    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Pausou Reparo para Compra', v_details, v_ctx.actor_name);
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
    v_ticket public.tickets%ROWTYPE;
    v_config jsonb := '{}'::jsonb;
    v_timer boolean;
    v_details text;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    SELECT t.* INTO v_ticket
      FROM public.tickets t
     WHERE t.id = p_ticket_id AND t.workspace_id = v_ctx.workspace_id AND t.deleted_at IS NULL
     FOR UPDATE OF t;
    SELECT COALESCE(w.tracker_config, '{}'::jsonb) INTO v_config
      FROM public.workspaces w WHERE w.id = v_ticket.workspace_id;

    IF NOT FOUND OR v_ticket.status <> 'Compra Peca' OR v_ticket.repair_paused_at IS NULL THEN
        RAISE EXCEPTION 'Esta OS não está com um reparo pausado aguardando compra.';
    END IF;
    IF NOT (v_ctx.is_admin OR v_ctx.is_attendant) THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode retomar o próprio reparo.';
    END IF;

    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    UPDATE public.tickets
       SET status = 'Andamento Reparo', parts_status = 'Recebido', parts_received_at = now(),
           repair_paused_at = NULL, repair_start_at = now(),
           repair_elapsed_seconds = CASE WHEN v_timer THEN COALESCE(repair_elapsed_seconds, 0) ELSE 0 END,
           repair_resume_count = COALESCE(repair_resume_count, 0) + 1, updated_at = now()
     WHERE id = v_ticket.id AND workspace_id = v_ctx.workspace_id;

    UPDATE public.ticket_appointments
       SET status = 'in_progress', actual_start = COALESCE(actual_start, now()),
           updated_by_user_id = v_ctx.actor_user_id,
           updated_by_employee_id = v_ctx.actor_employee_id, updated_at = now()
     WHERE id = (
        SELECT a.id FROM public.ticket_appointments a
         WHERE a.workspace_id = v_ctx.workspace_id AND a.ticket_id = v_ticket.id
           AND a.appointment_type = 'repair' AND a.status = 'scheduled' AND a.deleted_at IS NULL
         ORDER BY a.created_at DESC LIMIT 1
     );

    v_details := format(
        'Reparo da OS **%s** — aparelho **%s** do cliente **%s** — foi retomado por **%s** após a compra das peças. Novo ciclo iniciado.',
        COALESCE(v_ticket.os_number, 'não informada'), COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado'), v_ctx.actor_name);
    IF v_timer THEN
        v_details := v_details || format(' Tempo já contabilizado: **%s segundos**.', COALESCE(v_ticket.repair_elapsed_seconds, 0));
    END IF;
    INSERT INTO public.ticket_logs(ticket_id, action, details, user_name)
    VALUES (v_ticket.id, 'Retomou Reparo após Compra', v_details, v_ctx.actor_name);
    RETURN jsonb_build_object('success', true,
        'elapsed_seconds', CASE WHEN v_timer THEN COALESCE(v_ticket.repair_elapsed_seconds, 0) ELSE 0 END);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_technician_schedule(p_technician_id uuid, p_view text, p_reference_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
    v_ws_id uuid;
    v_end_date date;
    v_tz text := 'America/Sao_Paulo';
    v_start_ts timestamptz;
    v_end_ts timestamptz;
BEGIN
    SELECT * INTO v_ctx FROM public.get_current_actor_context();
    v_ws_id := v_ctx.workspace_id;

    IF NOT EXISTS (SELECT 1 FROM public.employees WHERE id = p_technician_id AND workspace_id = v_ws_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Técnico não encontrado ou não pertence ao workspace.';
    END IF;

    -- Validar permissão
    IF NOT v_ctx.is_admin AND NOT v_ctx.is_attendant AND (NOT v_ctx.is_technician OR p_technician_id IS DISTINCT FROM v_ctx.actor_employee_id) THEN
        RAISE EXCEPTION 'Acesso negado: Técnico só pode ver a própria agenda.';
    END IF;

    IF p_view = 'day' THEN
        v_end_date := p_reference_date;
    ELSIF p_view = 'week' THEN
        v_end_date := p_reference_date + 6;
    ELSE
        RAISE EXCEPTION 'View inválida. Use day ou week.';
    END IF;

    v_start_ts := (p_reference_date::timestamp AT TIME ZONE v_tz);
    v_end_ts := ((v_end_date + 1)::timestamp AT TIME ZONE v_tz);

    RETURN (
        WITH apps AS (
            SELECT a.id, a.ticket_id, a.appointment_type, a.scheduled_start, a.scheduled_end, a.status, a.notes, 
                   t.os_number, t.client_name, t.device_model, t.defect_reported, t.analysis_deadline, t.deadline
            FROM public.ticket_appointments a
            JOIN public.tickets t ON t.id = a.ticket_id
            WHERE a.technician_id = p_technician_id
              AND a.workspace_id = v_ws_id
              AND a.deleted_at IS NULL
              AND t.deleted_at IS NULL
              AND a.scheduled_start >= v_start_ts
              AND a.scheduled_end <= v_end_ts
        ),
        blocks AS (
            SELECT block_id AS id, block_type, start_at, end_at, reason
            FROM public.get_expanded_blocks(v_ws_id, p_technician_id, p_reference_date, v_end_date)
        )
        SELECT jsonb_build_object(
            'technician_id', p_technician_id,
            'start_date', p_reference_date,
            'end_date', v_end_date,
            'view', p_view,
            'appointments', COALESCE((SELECT jsonb_agg(row_to_json(apps)) FROM apps), '[]'::jsonb),
            'blocks', COALESCE((SELECT jsonb_agg(row_to_json(blocks)) FROM blocks), '[]'::jsonb),
            'counts', jsonb_build_object(
                'total_appointments', (SELECT COUNT(*) FROM apps WHERE status != 'cancelled'),
                'total_blocks', (SELECT COUNT(*) FROM blocks)
            )
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_client_ticket_details_public(p_ticket_id uuid, p_public_token uuid)
 RETURNS TABLE(id uuid, os_number text, device_model text, status text, deadline timestamp with time zone, priority_requested boolean, pickup_available boolean, created_at timestamp with time zone, whatsapp_number text, tracker_config jsonb, delivery_method text, carrier_name text, tracking_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    t.id,
    t.os_number,
    t.device_model,
    t.status,
    t.deadline,
    t.priority_requested,
    t.pickup_available,
    t.created_at,
    w.whatsapp_number,
    w.tracker_config,
    t.delivery_method,
    t.carrier_name,
    t.tracking_code
  FROM public.tickets t
  JOIN public.workspaces w ON w.id = t.workspace_id
  WHERE
    t.id = p_ticket_id
    AND t.public_token = p_public_token
    AND t.deleted_at IS NULL
    AND public.aida_config_bool(COALESCE(w.tracker_config, '{}'::jsonb), 'modules', 'public_tracker', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_warranty_analysis(p_ticket_id uuid, p_covered boolean, p_report text, p_needs_parts boolean DEFAULT false, p_parts text DEFAULT NULL::text, p_tech_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_parts_enabled boolean;
    v_target_status text;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket_id is null or p_covered is null then
        raise exception 'Informe a OS e a decisao da garantia.';
    end if;
    if length(btrim(coalesce(p_report, ''))) < 20 then
        raise exception 'Preencha um laudo tecnico com pelo menos 20 caracteres.';
    end if;

    select *
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null
     for update;

    if not found or not v_ticket.warranty_claim or v_ticket.warranty_status <> 'pending' then
        raise exception 'Este retorno nao esta aguardando a decisao da garantia.';
    end if;
    if v_ticket.status <> 'Analise Tecnica' then
        raise exception 'A decisao da garantia so pode ser registrada durante a analise tecnica.';
    end if;
    if not (
        coalesce(v_ctx.is_admin, false)
        or (
            coalesce(v_ctx.is_technician, false)
            and coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a analise.';
    end if;

    v_parts_enabled := coalesce(public.aida_warranty_parts_control_enabled(), true);

    if coalesce(p_needs_parts, false) and not coalesce(v_parts_enabled, true) then
        raise exception 'O controle de compra de pecas esta desativado.';
    end if;
    if coalesce(p_needs_parts, false) and length(btrim(coalesce(p_parts, ''))) < 2 then
        raise exception 'Informe as pecas necessarias.';
    end if;

    v_target_status := case
        when not p_covered then 'Aprovacao'
        when coalesce(p_needs_parts, false) then 'Compra Peca'
        else 'Andamento Reparo'
    end;

    update public.tickets t
       set warranty_status = case when p_covered then 'covered' else 'not_covered' end,
           warranty_technical_report = btrim(p_report),
           warranty_needs_parts = coalesce(p_needs_parts, false),
           parts_needed = case when coalesce(p_needs_parts, false) then btrim(p_parts) else null end,
           parts_status = case when coalesce(p_needs_parts, false) then 'Pendente' else 'N/A' end,
           budget_status = case when p_covered then 'Aprovado' else 'Pendente' end,
           tech_notes = coalesce(p_tech_notes, t.tech_notes),
           previous_status = t.status,
           status = v_target_status,
           updated_at = now()
     where t.id = v_ticket.id
     returning * into v_ticket;

    return to_jsonb(v_ticket);
end;
$function$;

CREATE OR REPLACE FUNCTION public.link_warranty_paid_ticket(p_claim_ticket_id uuid, p_paid_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_claim public.tickets%rowtype;
    v_paid public.tickets%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Somente administradores e atendentes podem concluir a conversao.';
    end if;

    select *
      into v_claim
      from public.tickets t
     where t.id = p_claim_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null
     for update;

    if not found then
        raise exception 'Retorno em garantia nao encontrado.';
    end if;

    select *
      into v_paid
      from public.tickets t
     where t.id = p_paid_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Nova OS paga nao encontrada.';
    end if;
    if not v_claim.warranty_claim or v_claim.warranty_status <> 'not_covered' then
        raise exception 'O retorno nao esta disponivel para conversao.';
    end if;
    if v_claim.warranty_converted_ticket_id is not null then
        raise exception 'Este retorno ja foi convertido.';
    end if;
    if v_paid.warranty_source_claim_id is distinct from v_claim.id
       or v_paid.customer_id is distinct from v_claim.customer_id then
        raise exception 'A nova OS nao possui o vinculo esperado com o retorno.';
    end if;

    update public.tickets t
       set warranty_converted_ticket_id = v_paid.id,
           previous_status = t.status,
           status = 'Finalizado',
           budget_status = 'Aprovado',
           repair_successful = false,
           delivered_at = now(),
           updated_at = now()
     where t.id = v_claim.id
     returning * into v_claim;

    return to_jsonb(v_claim);
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_repair_with_inventory(p_ticket_id uuid, p_success boolean, p_usage jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_config jsonb;
    v_timer boolean;
    v_elapsed integer;
    v_next_status text;
    v_reservation record;
    v_usage jsonb;
    v_remaining numeric(14,3);
    v_used numeric(14,3);
    v_unused numeric(14,3);
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    if p_usage is null or jsonb_typeof(p_usage) <> 'array'
       or jsonb_array_length(p_usage) > 100 then
        raise exception 'Confirme o uso das pecas reservadas.';
    end if;

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null
    for update;

    if not found or v_ticket.status <> 'Andamento Reparo'
       or v_ticket.repair_start_at is null then
        raise exception 'A OS nao esta disponivel para finalizar reparo.';
    end if;
    if not (
        v_ctx.is_admin
        or (
            v_ctx.is_technician
            and coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode finalizar o reparo.';
    end if;

    for v_reservation in
        select r.*, tp.ticket_id
        from public.inventory_reservations r
        join public.ticket_part_items tp
          on tp.workspace_id = r.workspace_id and tp.id = r.ticket_part_item_id
        where r.workspace_id = v_ctx.workspace_id
          and tp.ticket_id = p_ticket_id
          and r.status = 'active'
        order by r.item_id, r.location_id, r.id
        for update of r
    loop
        v_remaining := v_reservation.reserved_quantity
            - v_reservation.consumed_quantity
            - v_reservation.released_quantity;
        if v_remaining <= 0 then continue; end if;

        select value into v_usage
        from jsonb_array_elements(p_usage)
        where value ->> 'reservation_id' = v_reservation.id::text
        limit 1;
        if v_usage is null then
            raise exception 'Confirme a quantidade usada de todas as pecas reservadas.';
        end if;
        begin
            v_used := (v_usage ->> 'used_quantity')::numeric;
        exception when others then
            raise exception 'Quantidade utilizada invalida.';
        end;
        if v_used is null or v_used < 0 or v_used > v_remaining then
            raise exception 'A quantidade usada nao pode exceder a reserva.';
        end if;
        v_unused := v_remaining - v_used;

        update public.inventory_balances
        set physical_quantity = physical_quantity - v_used,
            reserved_quantity = reserved_quantity - v_remaining,
            updated_at = now()
        where workspace_id = v_ctx.workspace_id
          and item_id = v_reservation.item_id
          and location_id = v_reservation.location_id;

        if v_used > 0 then
            insert into public.inventory_movements(
                workspace_id, item_id, location_id, movement_type,
                physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
                reason, actor_user_id, actor_employee_id, actor_name
            ) values (
                v_ctx.workspace_id, v_reservation.item_id,
                v_reservation.location_id, 'consume',
                -v_used, -v_used, p_ticket_id, v_reservation.ticket_part_item_id,
                'Peca utilizada no reparo',
                v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
            );
        end if;
        if v_unused > 0 then
            insert into public.inventory_movements(
                workspace_id, item_id, location_id, movement_type,
                physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
                reason, actor_user_id, actor_employee_id, actor_name
            ) values (
                v_ctx.workspace_id, v_reservation.item_id,
                v_reservation.location_id, 'release',
                0, -v_unused, p_ticket_id, v_reservation.ticket_part_item_id,
                'Peca reservada nao utilizada',
                v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
            );
        end if;

        update public.inventory_reservations
        set consumed_quantity = consumed_quantity + v_used,
            released_quantity = released_quantity + v_unused,
            status = case when v_used > 0 then 'consumed' else 'released' end,
            updated_at = now()
        where id = v_reservation.id and workspace_id = v_ctx.workspace_id;
    end loop;

    update public.ticket_part_items tp
    set status = case
            when exists (
                select 1 from public.inventory_reservations r
                where r.workspace_id = tp.workspace_id
                  and r.ticket_part_item_id = tp.id
                  and r.consumed_quantity > 0
            ) then 'consumed'
            else 'released'
        end,
        updated_at = now()
    where tp.workspace_id = v_ctx.workspace_id
      and tp.ticket_id = p_ticket_id
      and tp.status in ('reserved', 'ready');

    perform private.inventory_sync_ticket_summary(v_ctx.workspace_id, p_ticket_id);

    select coalesce(w.tracker_config, '{}'::jsonb)
    into v_config from public.workspaces w where w.id = v_ctx.workspace_id;
    v_timer := public.aida_config_bool(v_config, 'workflow', 'repair_timer', true);
    v_elapsed := case
        when v_timer then coalesce(v_ticket.repair_elapsed_seconds, 0)
            + greatest(0, extract(epoch from (now() - v_ticket.repair_start_at))::integer)
        else 0
    end;
    v_next_status := case
        when p_success and public.aida_config_bool(v_config, 'workflow', 'final_test', true)
            then 'Teste Final'
        else 'Retirada Cliente'
    end;

    update public.tickets
    set status = v_next_status,
        repair_successful = p_success,
        repair_elapsed_seconds = v_elapsed,
        repair_end_at = now(),
        repair_start_at = null,
        repair_paused_at = null,
        updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_ticket_id;

    update public.ticket_appointments
    set status = 'completed',
        actual_start = coalesce(actual_start, now()),
        actual_end = now(),
        updated_by_user_id = v_ctx.actor_user_id,
        updated_by_employee_id = v_ctx.actor_employee_id,
        updated_at = now()
    where id = (
        select a.id from public.ticket_appointments a
        where a.workspace_id = v_ctx.workspace_id
          and a.ticket_id = p_ticket_id
          and a.appointment_type = 'repair'
          and a.status in ('scheduled', 'in_progress')
          and a.deleted_at is null
        order by a.created_at desc limit 1
    );

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        'Finalizou Reparo',
        format(
            'O reparo da **OS %s**, aparelho **%s** de **%s**, foi finalizado por **%s** com resultado **%s**. As peças utilizadas foram baixadas e as não utilizadas voltaram ao disponível.%s',
            coalesce(v_ticket.os_number, 'não informada'),
            coalesce(v_ticket.device_model, 'não informado'),
            coalesce(v_ticket.client_name, 'não informado'),
            v_ctx.actor_name,
            case when p_success then 'sucesso' else 'sem reparo' end,
            case when v_timer
                then format(' Tempo total: **%s segundos**.', v_elapsed)
                else ''
            end
        ),
        v_ctx.actor_name
    );

    return jsonb_build_object(
        'success', true,
        'status', v_next_status,
        'elapsed_seconds', v_elapsed
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_warranty_analysis_with_inventory(p_ticket_id uuid, p_report text, p_tech_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_parts text;
    v_updated jsonb;
    v_allocation jsonb;
    v_route text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    select * into v_ticket
    from public.tickets t
    where t.workspace_id = v_ctx.workspace_id
      and t.id = p_ticket_id
      and t.deleted_at is null
    for update;
    if not found or not v_ticket.warranty_claim
       or v_ticket.warranty_status <> 'pending'
       or v_ticket.status <> 'Analise Tecnica' then
        raise exception 'Este retorno nao esta aguardando a decisao da garantia.';
    end if;
    if not (
        v_ctx.is_admin
        or (
            v_ctx.is_technician
            and coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a garantia.';
    end if;

    select string_agg(
        format('%s x %s', tp.requested_quantity, tp.requested_name_snapshot),
        ', ' order by tp.created_at, tp.id
    ) into v_parts
    from public.ticket_part_items tp
    where tp.workspace_id = v_ctx.workspace_id
      and tp.ticket_id = p_ticket_id
      and tp.request_stage = 'warranty'
      and tp.status not in ('cancelled', 'released', 'consumed');
    if nullif(btrim(coalesce(v_parts, '')), '') is null then
        raise exception 'Selecione as pecas necessarias para a garantia.';
    end if;

    v_updated := public.complete_warranty_analysis(
        p_ticket_id,
        true,
        p_report,
        true,
        v_parts,
        p_tech_notes
    );
    v_allocation := private.inventory_allocate_ticket_parts(v_ctx.workspace_id, p_ticket_id);
    v_route := case
        when coalesce((v_allocation ->> 'fully_reserved')::boolean, false)
            then 'repair'
        else 'purchase'
    end;

    update public.tickets t
    set status = case when v_route = 'repair' then 'Andamento Reparo' else 'Compra Peca' end,
        budget_status = 'Aprovado',
        parts_status = case when v_route = 'repair' then 'Reservado' else 'Pendente' end,
        updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_ticket_id
    returning to_jsonb(t.*) into v_updated;

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        case when v_route = 'repair'
            then 'Reservou Pecas da Garantia'
            else 'Encaminhou Garantia para Compra'
        end,
        format(
            'A garantia da **OS %s** foi confirmada por **%s**. %s',
            coalesce(v_ticket.os_number, 'nao informada'),
            v_ctx.actor_name,
            case when v_route = 'repair'
                then 'Todas as pecas foram reservadas e a OS seguiu para **Reparo**.'
                else 'O saldo disponivel foi reservado e somente a falta seguiu para **Compra de Pecas**.'
            end
        ),
        v_ctx.actor_name
    );

    return v_updated || jsonb_build_object(
        'route', v_route,
        'missing_quantity', coalesce((v_allocation ->> 'missing_quantity')::numeric, 0),
        'shortages', coalesce(v_allocation -> 'shortages', '[]'::jsonb)
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.return_ticket_inventory(p_reservation_id uuid, p_quantity numeric, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_reservation public.inventory_reservations%rowtype;
    v_part public.ticket_part_items%rowtype;
    v_ticket public.tickets%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');
    if p_quantity is null or p_quantity <= 0
       or length(btrim(coalesce(p_reason, ''))) < 5 then
        raise exception 'Informe quantidade e motivo da devolucao.';
    end if;
    select * into v_reservation
    from public.inventory_reservations r
    where r.workspace_id = v_ctx.workspace_id and r.id = p_reservation_id
    for update;
    if not found or v_reservation.consumed_quantity - v_reservation.returned_quantity < p_quantity then
        raise exception 'Quantidade de devolucao invalida.';
    end if;
    select * into v_part from public.ticket_part_items tp
    where tp.workspace_id = v_ctx.workspace_id and tp.id = v_reservation.ticket_part_item_id;
    select * into v_ticket from public.tickets t
    where t.workspace_id = v_ctx.workspace_id and t.id = v_part.ticket_id;
    if v_ticket.deleted_at is not null and not v_ctx.is_admin then
        raise exception 'Acesso negado: chamado excluido.' using errcode='42501';
    end if;
    if not (
        v_ctx.is_admin
        or (
            v_ctx.is_technician
            and coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
        )
    ) then raise exception 'Somente o tecnico responsavel ou um administrador pode devolver a peca.'; end if;

    update public.inventory_balances
    set physical_quantity = physical_quantity + p_quantity, updated_at = now()
    where workspace_id = v_ctx.workspace_id
      and item_id = v_reservation.item_id
      and location_id = v_reservation.location_id;
    update public.inventory_reservations
    set returned_quantity = returned_quantity + p_quantity, updated_at = now()
    where workspace_id = v_ctx.workspace_id and id = p_reservation_id;
    insert into public.inventory_movements(
        workspace_id, item_id, location_id, movement_type,
        physical_delta, reserved_delta, ticket_id, ticket_part_item_id,
        reason, actor_user_id, actor_employee_id, actor_name
    ) values (
        v_ctx.workspace_id, v_reservation.item_id, v_reservation.location_id,
        'return', p_quantity, 0, v_ticket.id, v_part.id,
        btrim(p_reason), v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
    );
    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        v_ticket.id,
        'Devolveu Peca ao Estoque',
        format(
            '**%s** devolveu **%s x %s** da **OS %s** ao estoque. Motivo: **%s**.',
            v_ctx.actor_name, p_quantity, v_part.requested_name_snapshot,
            coalesce(v_ticket.os_number, 'nao informada'), btrim(p_reason)
        ),
        v_ctx.actor_name
    );
    return jsonb_build_object('success', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_ticket_appointments(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket record;
    v_is_tester boolean;
begin
    select * into v_ctx from public.get_current_actor_context();
    v_is_tester := 'tester' = any(coalesce(v_ctx.actor_roles, '{}'::text[]));

    select t.technician_id, t.status
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Chamado não encontrado ou não pertence ao workspace.';
    end if;
    if not (
        v_ctx.is_admin
        or v_ctx.is_attendant
        or (
            v_ctx.is_technician and (
                coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
                or (v_ticket.technician_id is null and
                    v_ticket.status in ('Analise Tecnica', 'Andamento Reparo', 'Teste Final'))
            )
        )
        or (v_is_tester and v_ticket.status = 'Teste Final')
    ) then
        raise exception 'Acesso negado aos agendamentos deste chamado.';
    end if;

    return private.get_ticket_appointments(p_ticket_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_ticket_appointment(p_ticket_id uuid, p_technician_id uuid, p_appointment_type text, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket_id is null or p_technician_id is null then
        raise exception 'Chamado e técnico são obrigatórios.';
    end if;
    if p_appointment_type is null or p_appointment_type not in ('analysis', 'repair') then
        raise exception 'Tipo de agendamento inválido. Use analysis ou repair.';
    end if;
    if p_scheduled_start is null or p_scheduled_end is null or p_scheduled_end <= p_scheduled_start then
        raise exception 'Período do agendamento inválido.';
    end if;

    select t.technician_id, t.status
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Chamado não encontrado ou não pertence ao workspace.';
    end if;
    if not exists (
        select 1 from public.employees e
        where e.id = p_technician_id
          and e.workspace_id = v_ctx.workspace_id
          and e.deleted_at is null
          and 'tecnico' = any(coalesce(e.roles, '{}'::text[]))
    ) then
        raise exception 'Técnico não encontrado ou não pertence ao workspace.';
    end if;

    if not (v_ctx.is_admin or v_ctx.is_attendant) then
        if not v_ctx.is_technician
           or p_technician_id <> v_ctx.actor_employee_id
           or not (
               coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
               or (v_ticket.technician_id is null and
                   v_ticket.status in ('Analise Tecnica', 'Andamento Reparo', 'Teste Final'))
           ) then
            raise exception 'Acesso negado para criar este agendamento.';
        end if;
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            pg_catalog.concat_ws(
                ':', 'aida_ticket_appointment', p_ticket_id::text, p_appointment_type
            ),
            0
        )
    );

    return private.create_ticket_appointment(
        p_ticket_id, p_technician_id, p_appointment_type,
        p_scheduled_start, p_scheduled_end, p_notes
    );
end;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_ticket_warranty()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_origin public.tickets%rowtype;
    v_claim public.tickets%rowtype;
    v_days integer;
    v_start timestamptz;
    v_expiry timestamptz;
begin
    select * into v_ctx from public.get_current_actor_context();

    if new.workspace_id is distinct from v_ctx.workspace_id then
        raise exception 'A OS de garantia deve pertencer a empresa atual.';
    end if;

    v_days := coalesce(public.aida_warranty_days(), 90);

    if tg_op = 'INSERT' then
        if new.warranty_claim then
            if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
                raise exception 'Somente administradores e atendentes podem abrir um retorno em garantia.';
            end if;
            if not coalesce(public.aida_warranty_enabled(), true) then
                raise exception 'A abertura de retornos em garantia esta desativada.';
            end if;
            if new.warranty_origin_ticket_id is null then
                raise exception 'Selecione a OS original da garantia.';
            end if;

            select *
              into v_origin
              from public.tickets t
             where t.id = new.warranty_origin_ticket_id
               and t.workspace_id = new.workspace_id
               and t.deleted_at is null
             for share;

            if not found then
                raise exception 'OS original nao encontrada ou fora da empresa.';
            end if;
            if v_origin.warranty_claim then
                raise exception 'A garantia deve ser vinculada a uma OS de servico original.';
            end if;
            if v_origin.customer_id is null or new.customer_id is distinct from v_origin.customer_id then
                raise exception 'O retorno deve usar o mesmo cliente da OS original.';
            end if;
            if v_origin.repair_successful is distinct from true
               or v_origin.delivered_at is null
               or v_origin.status <> 'Finalizado' then
                raise exception 'A OS original precisa estar finalizada, entregue e com reparo concluido com sucesso.';
            end if;

            v_start := coalesce(v_origin.warranty_start_at, v_origin.delivered_at);
            v_expiry := coalesce(
                v_origin.warranty_expires_at,
                v_start + make_interval(days => coalesce(v_origin.warranty_days, v_days))
            );
            if v_expiry < now() then
                raise exception 'A garantia desta OS expirou em %.', to_char(v_expiry at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
            end if;
            if exists (
                select 1
                  from public.tickets active_claim
                 where active_claim.workspace_id = new.workspace_id
                   and active_claim.warranty_claim
                   and active_claim.warranty_origin_ticket_id = v_origin.id
                   and active_claim.deleted_at is null
                   and active_claim.status <> 'Finalizado'
            ) then
                raise exception 'Ja existe um retorno em garantia aberto para esta OS.';
            end if;

            new.customer_id := v_origin.customer_id;
            new.client_name := v_origin.client_name;
            new.contact_info := coalesce(new.contact_info, v_origin.contact_info);
            new.device_model := v_origin.device_model;
            new.serial_number := v_origin.serial_number;
            new.warranty_source_claim_id := null;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := 'pending';
            new.warranty_days := coalesce(v_origin.warranty_days, v_days);
            new.warranty_start_at := v_start;
            new.warranty_expires_at := v_expiry;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        elsif new.warranty_source_claim_id is not null then
            if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
                raise exception 'Somente administradores e atendentes podem converter um retorno em uma nova OS.';
            end if;

            select *
              into v_claim
              from public.tickets t
             where t.id = new.warranty_source_claim_id
               and t.workspace_id = new.workspace_id
               and t.deleted_at is null
             for share;

            if not found or not v_claim.warranty_claim or v_claim.warranty_status <> 'not_covered' then
                raise exception 'O retorno informado nao esta aguardando uma nova OS paga.';
            end if;
            if v_claim.customer_id is null or new.customer_id is distinct from v_claim.customer_id then
                raise exception 'A nova OS deve usar o mesmo cliente do retorno.';
            end if;
            if v_claim.warranty_converted_ticket_id is not null then
                raise exception 'Este retorno ja foi convertido em uma nova OS.';
            end if;

            new.warranty_claim := false;
            new.warranty_origin_ticket_id := v_claim.warranty_origin_ticket_id;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := null;
            new.warranty_days := null;
            new.warranty_start_at := null;
            new.warranty_expires_at := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        else
            new.warranty_claim := false;
            new.warranty_origin_ticket_id := null;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := null;
            new.warranty_days := null;
            new.warranty_start_at := null;
            new.warranty_expires_at := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        end if;
    else
        if old.warranty_claim is distinct from new.warranty_claim
           or old.warranty_origin_ticket_id is distinct from new.warranty_origin_ticket_id
           or old.warranty_source_claim_id is distinct from new.warranty_source_claim_id then
            raise exception 'Os vinculos da garantia nao podem ser alterados depois da abertura.';
        end if;

        if old.warranty_converted_ticket_id is distinct from new.warranty_converted_ticket_id
           and not (
                old.warranty_claim
                and old.warranty_status = 'not_covered'
                and old.warranty_converted_ticket_id is null
                and new.warranty_converted_ticket_id is not null
                and (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false))
           ) then
            raise exception 'O vinculo da nova OS paga e protegido.';
        end if;

        if old.warranty_claim then
            if new.warranty_status is distinct from old.warranty_status then
                if old.warranty_status is distinct from 'pending'
                   or new.warranty_status is null
                   or new.warranty_status not in ('covered', 'not_covered')
                   or old.status <> 'Analise Tecnica' then
                    raise exception 'Decisao de garantia invalida para a etapa atual.';
                end if;
                if not (
                    coalesce(v_ctx.is_admin, false)
                    or (
                        coalesce(v_ctx.is_technician, false)
                        and coalesce(old.technician_id = v_ctx.actor_employee_id, false)
                    )
                ) then
                    raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a analise da garantia.';
                end if;
                if length(btrim(coalesce(new.warranty_technical_report, ''))) < 20 then
                    raise exception 'Preencha um laudo tecnico com pelo menos 20 caracteres.';
                end if;
                if coalesce(new.warranty_needs_parts, false)
                   and length(btrim(coalesce(new.parts_needed, ''))) < 2 then
                    raise exception 'Informe as pecas necessarias.';
                end if;
                if coalesce(new.warranty_needs_parts, false)
                   and not coalesce(public.aida_warranty_parts_control_enabled(), true) then
                    raise exception 'O controle de compra de pecas esta desativado.';
                end if;

                new.warranty_decided_at := now();
                new.warranty_decided_by := coalesce(v_ctx.actor_employee_id, v_ctx.actor_user_id);
                new.warranty_decided_by_name := v_ctx.actor_name;
            elsif new.warranty_status = 'pending' then
                new.warranty_technical_report := null;
                new.warranty_needs_parts := null;
                new.warranty_decided_at := null;
                new.warranty_decided_by := null;
                new.warranty_decided_by_name := null;
            end if;
        else
            new.warranty_status := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        end if;
    end if;

    -- A successful paid service starts its own warranty when it is delivered.
    -- Warranty claims never reset or extend the original coverage.
    if not new.warranty_claim
       and new.repair_successful is true
       and new.delivered_at is not null then
        new.warranty_days := case
            when tg_op = 'UPDATE' then coalesce(old.warranty_days, v_days)
            else v_days
        end;
        new.warranty_start_at := new.delivered_at;
        new.warranty_expires_at := new.delivered_at + make_interval(days => new.warranty_days);
    end if;

    return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.request_ticket_inventory_parts(p_ticket_id uuid, p_items jsonb, p_stage text, p_allocate_now boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_item jsonb;
    v_catalog public.inventory_items%rowtype;
    v_quantity numeric(14,3);
    v_result jsonb;
    v_route text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    if p_stage not in ('analysis', 'direct_repair', 'repair', 'warranty') then
        raise exception 'Etapa de solicitacao invalida.';
    end if;
    if p_items is null or jsonb_typeof(p_items) <> 'array'
       or jsonb_array_length(p_items) < 1
       or jsonb_array_length(p_items) > 50 then
        raise exception 'Informe entre 1 e 50 itens.';
    end if;

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null
    for update;
    if not found then raise exception 'OS nao encontrada.'; end if;

    if p_stage in ('analysis', 'warranty') and v_ticket.status <> 'Analise Tecnica' then
        raise exception 'As pecas da analise so podem ser informadas durante a analise tecnica.';
    end if;
    if p_stage = 'repair' and (
        v_ticket.status <> 'Andamento Reparo' or v_ticket.repair_start_at is null
    ) then
        raise exception 'Inicie o reparo antes de solicitar uma nova peca.';
    end if;
    if p_stage in ('analysis', 'repair', 'warranty')
       and not (
            v_ctx.is_admin
            or (
                v_ctx.is_technician
                and coalesce(v_ticket.technician_id = v_ctx.actor_employee_id, false)
            )
       ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode solicitar estas pecas.';
    end if;
    if p_stage = 'direct_repair' and not (v_ctx.is_admin or v_ctx.is_attendant) then
        raise exception 'Somente administradores e atendentes podem preparar reparo direto.';
    end if;

    if p_stage is null or p_allocate_now is null then
        raise exception 'Etapa e decisao de reserva sao obrigatorias.' using errcode='22023';
    end if;
    if p_stage in ('analysis','warranty') and p_allocate_now then
        raise exception 'A reserva exige aprovacao do orcamento ou conclusao da garantia.' using errcode='42501';
    end if;
    if p_stage in ('direct_repair','repair') and (v_ticket.budget_status is distinct from 'Aprovado' or v_ticket.status not in ('Andamento Reparo','Compra Peca')) then
        raise exception 'A reserva para reparo exige orcamento aprovado e fase de reparo ou compra.' using errcode='42501';
    end if;

    if exists (
        select 1
        from public.ticket_part_items tp
        where tp.workspace_id = v_ctx.workspace_id
          and tp.ticket_id = p_ticket_id
          and tp.request_stage = p_stage
          and tp.status not in ('cancelled', 'released', 'consumed')
    ) then
        raise exception 'Esta OS ja possui uma solicitacao ativa nesta etapa.';
    end if;

    for v_item in select value from jsonb_array_elements(p_items)
    loop
        begin
            v_quantity := (v_item ->> 'quantity')::numeric;
            select * into v_catalog
            from public.inventory_items i
            where i.id = (v_item ->> 'item_id')::uuid
              and i.workspace_id = v_ctx.workspace_id
              and i.active;
        exception when others then
            raise exception 'Item ou quantidade invalida na solicitacao.';
        end;

        if not found then raise exception 'Item do estoque nao encontrado.'; end if;
        if v_quantity is null or v_quantity <= 0 or v_quantity > 999999 then
            raise exception 'Quantidade invalida para %.', v_catalog.name;
        end if;
        if not v_catalog.allow_decimal and v_quantity <> trunc(v_quantity) then
            raise exception '% aceita apenas quantidades inteiras.', v_catalog.name;
        end if;

        if nullif(v_item ->> 'original_item_id', '') is not null and not exists (
            select 1 from public.inventory_item_relations rel
            where rel.workspace_id = v_ctx.workspace_id
              and rel.source_item_id = (v_item ->> 'original_item_id')::uuid
              and rel.target_item_id = v_catalog.id
              and rel.relation_type = v_item ->> 'substitution_type'
        ) then
            raise exception 'A alternativa selecionada nao possui vinculo valido.';
        end if;

        insert into public.ticket_part_items(
            workspace_id, ticket_id, requested_item_id, original_item_id,
            substitution_type, requested_name_snapshot,
            requested_quantity, request_stage, status, notes,
            requested_by_user_id, requested_by_employee_id, requested_by_name
        ) values (
            v_ctx.workspace_id, p_ticket_id, v_catalog.id,
            nullif(v_item ->> 'original_item_id', '')::uuid,
            nullif(v_item ->> 'substitution_type', ''), v_catalog.name,
            v_quantity, p_stage,
            case when p_allocate_now then 'needed' else 'pending_approval' end,
            nullif(btrim(v_item ->> 'notes'), ''),
            v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
        );

        if nullif(v_item ->> 'original_item_id', '') is not null then
            insert into public.ticket_logs(ticket_id, action, details, user_name)
            select p_ticket_id, 'Escolheu Peça Alternativa', format(
                '**%s** escolheu **%s** como %s de **%s** para a **OS %s**.',
                v_ctx.actor_name,
                v_catalog.name,
                case when v_item ->> 'substitution_type' = 'equivalent' then 'equivalente' else 'substituta' end,
                original.name,
                coalesce(v_ticket.os_number, 'não informada')
            ), v_ctx.actor_name
            from public.inventory_items original
            where original.workspace_id = v_ctx.workspace_id
              and original.id = (v_item ->> 'original_item_id')::uuid;
        end if;
    end loop;

    perform private.inventory_sync_ticket_summary(v_ctx.workspace_id, p_ticket_id);

    if not p_allocate_now then
        insert into public.ticket_logs(ticket_id, action, details, user_name)
        values (
            p_ticket_id,
            'Registrou Peças Necessárias',
            format(
                '**%s** registrou as peças necessárias para a **OS %s**. A reserva será feita após a aprovação.',
                v_ctx.actor_name, coalesce(v_ticket.os_number, 'não informada')
            ),
            v_ctx.actor_name
        );
        return jsonb_build_object(
            'success', true,
            'route', 'pending_approval',
            'fully_reserved', false,
            'shortages', '[]'::jsonb
        );
    end if;

    v_result := private.inventory_allocate_ticket_parts(v_ctx.workspace_id, p_ticket_id);

    if coalesce((v_result ->> 'fully_reserved')::boolean, false) then
        v_route := 'repair';
        if p_stage = 'direct_repair' then
            update public.tickets
            set status = 'Andamento Reparo', parts_status = 'Reservado', updated_at = now()
            where workspace_id = v_ctx.workspace_id and id = p_ticket_id;
        end if;
        insert into public.ticket_logs(ticket_id, action, details, user_name)
        values (
            p_ticket_id,
            'Reservou Peças do Estoque',
            format(
                '**%s** reservou todas as peças da **OS %s**. O reparo pode continuar sem pausa.',
                v_ctx.actor_name, coalesce(v_ticket.os_number, 'não informada')
            ),
            v_ctx.actor_name
        );
    else
        v_route := 'purchase';
        if p_stage = 'repair' then
            perform private.inventory_pause_repair_for_shortage(
                v_ctx.workspace_id, p_ticket_id, v_result -> 'shortages'
            );
        else
            update public.tickets
            set status = 'Compra Peca', parts_status = 'Pendente', updated_at = now()
            where workspace_id = v_ctx.workspace_id and id = p_ticket_id;
            insert into public.ticket_logs(ticket_id, action, details, user_name)
            values (
                p_ticket_id,
                'Encaminhou Faltas para Compra',
                format(
                    '**%s** reservou o saldo disponível da **OS %s** e encaminhou somente a quantidade faltante para compra.',
                    v_ctx.actor_name, coalesce(v_ticket.os_number, 'não informada')
                ),
                v_ctx.actor_name
            );
        end if;
    end if;

    return v_result || jsonb_build_object('success', true, 'route', v_route);
end;
$function$;

CREATE FUNCTION private.can_upload_ticket_photo(p_name text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_workspace uuid;v_ticket_id uuid;v_ticket record;v_ctx record;
BEGIN
  BEGIN
    v_workspace:=split_part(p_name,'/',1)::uuid;
    v_ticket_id:=split_part(p_name,'/',2)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN RETURN false; END;
  IF NOT private.has_workspace_permission(v_workspace,'ticket_photo_write') THEN RETURN false; END IF;
  SELECT * INTO v_ctx FROM private.workspace_actor(v_workspace);
  -- Check existence without RLS so an inaccessible existing ticket cannot look like a new draft.
  SELECT t.workspace_id,t.technician_id,t.status,t.deleted_at INTO v_ticket FROM public.tickets t WHERE t.id=v_ticket_id;
  IF NOT FOUND THEN RETURN true; END IF;
  IF v_ticket.workspace_id IS DISTINCT FROM v_workspace OR v_ticket.deleted_at IS NOT NULL THEN RETURN false; END IF;
  RETURN v_ctx.is_admin OR v_ctx.is_attendant OR
    (v_ctx.is_technician AND (v_ticket.technician_id=v_ctx.actor_employee_id OR
     (v_ticket.technician_id IS NULL AND v_ticket.status IN ('Analise Tecnica','Andamento Reparo','Teste Final'))));
EXCEPTION WHEN insufficient_privilege THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION private.can_upload_ticket_photo(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.can_upload_ticket_photo(text) TO authenticated;

-- An explicit transition avoids returning a post-test row that the tester cannot read.
CREATE FUNCTION public.conclude_ticket_test(p_ticket_id uuid,p_status text,p_updates jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_ctx record;v_ticket public.tickets%rowtype;v_config jsonb;v_mode text;
 v_checklist jsonb;v_reason text;v_deadline timestamptz;v_priority text;v_note jsonb;v_action text;v_details text;
BEGIN
 SELECT * INTO v_ctx FROM public.get_current_actor_context();
 SELECT * INTO v_ticket FROM public.tickets t
 WHERE t.id=p_ticket_id AND t.workspace_id=v_ctx.workspace_id AND t.deleted_at IS NULL
   AND t.status='Teste Final' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Acesso negado: chamado nao disponivel para teste.' USING ERRCODE='42501';END IF;
 SELECT COALESCE(w.tracker_config,'{}'::jsonb) INTO v_config FROM public.workspaces w WHERE w.id=v_ctx.workspace_id;
 v_mode:=COALESCE(v_config->>'test_flow','kanban');
 IF NOT v_ctx.is_admin AND NOT
   (CASE WHEN v_mode='tester' THEN 'tester'=ANY(COALESCE(v_ctx.actor_roles,'{}'::text[]))
    ELSE v_ctx.is_technician AND COALESCE(v_ticket.technician_id=v_ctx.actor_employee_id,false) END) THEN
   RAISE EXCEPTION 'Acesso negado: permissao de teste final necessaria.' USING ERRCODE='42501';
 END IF;
 IF v_ticket.test_start_at IS NULL THEN RAISE EXCEPTION 'Inicie os testes antes de concluir.' USING ERRCODE='22023'; END IF;
 IF p_status NOT IN ('Retirada Cliente','Andamento Reparo','Terceirizado') OR p_status IS NULL THEN
   RAISE EXCEPTION 'Destino de teste invalido.' USING ERRCODE='22023';END IF;
 IF p_updates IS NULL OR jsonb_typeof(p_updates)<>'object' OR EXISTS(
   SELECT 1 FROM jsonb_object_keys(p_updates) k WHERE k NOT IN
     ('checklist_final_data','deadline','priority','test_notes','outsourced_deadline',
      'outsourced_return_count','outsourced_notes','repair_start_at','test_start_at')) THEN
   RAISE EXCEPTION 'Campos nao permitidos para conclusao do teste.' USING ERRCODE='42501';END IF;
 v_checklist:=CASE WHEN p_updates ? 'checklist_final_data' THEN p_updates->'checklist_final_data' ELSE v_ticket.checklist_final_data END;
 IF v_checklist IS NOT NULL AND (jsonb_typeof(v_checklist)<>'array' OR jsonb_array_length(v_checklist)>200) THEN
   RAISE EXCEPTION 'Checklist final invalido.' USING ERRCODE='22023';END IF;
 IF p_status='Retirada Cliente' THEN
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_updates) k WHERE k<>'checklist_final_data') THEN
     RAISE EXCEPTION 'Aprovacao do teste recebe somente o checklist final.' USING ERRCODE='42501';END IF;
   UPDATE public.tickets SET status=p_status,checklist_final_data=v_checklist,updated_at=now()
     WHERE id=v_ticket.id AND workspace_id=v_ctx.workspace_id;
   v_action:='Concluiu Testes';v_details:='Teste final aprovado pelo usuario autenticado.';
 ELSIF p_status='Terceirizado' THEN
   IF NOT v_ticket.is_outsourced THEN RAISE EXCEPTION 'Chamado nao terceirizado.' USING ERRCODE='22023';END IF;
   v_deadline:=NULLIF(p_updates->>'outsourced_deadline','')::timestamptz;
   v_reason:=NULLIF(btrim(p_updates->'outsourced_notes'->-1->>'text'),'');
   IF v_deadline IS NULL OR v_reason IS NULL OR length(v_reason)>4000 THEN
     RAISE EXCEPTION 'Informe motivo e prazo do retorno.' USING ERRCODE='22023';END IF;
   v_note:=jsonb_build_object('date',now(),'text',v_reason,'user',v_ctx.actor_name,
     'context','Retorno '||(COALESCE(v_ticket.outsourced_return_count,0)+1)::text||'x');
   UPDATE public.tickets SET status=p_status,checklist_final_data=v_checklist,
     outsourced_deadline=v_deadline,outsourced_return_count=COALESCE(v_ticket.outsourced_return_count,0)+1,
     outsourced_notes=COALESCE(v_ticket.outsourced_notes,'[]'::jsonb)||jsonb_build_array(v_note),
     test_start_at=NULL,updated_at=now() WHERE id=v_ticket.id AND workspace_id=v_ctx.workspace_id;
   v_action:='Devolveu para Terceiro';v_details:='Teste reprovado e retorno ao terceiro registrado: '||v_reason;
 ELSE
   v_deadline:=NULLIF(p_updates->>'deadline','')::timestamptz;
   v_priority:=COALESCE(NULLIF(btrim(p_updates->>'priority'),''),v_ticket.priority,'Normal');
   v_reason:=NULLIF(btrim(p_updates->'test_notes'->-1->>'text'),'');
   IF v_deadline IS NULL OR v_reason IS NULL OR length(v_reason)>4000 OR length(v_priority)>40 THEN
     RAISE EXCEPTION 'Informe motivo e novo prazo do reparo.' USING ERRCODE='22023';END IF;
   v_note:=jsonb_build_object('date',now(),'text',v_reason,'user',v_ctx.actor_name,
     'context',CASE WHEN v_ticket.is_outsourced THEN 'Falha de Terceiro' ELSE 'Reprova em Teste' END);
   UPDATE public.tickets SET status=p_status,checklist_final_data=v_checklist,
     deadline=v_deadline,priority=v_priority,repair_start_at=NULL,test_start_at=NULL,
     test_notes=COALESCE(v_ticket.test_notes,'[]'::jsonb)||jsonb_build_array(v_note),updated_at=now()
     WHERE id=v_ticket.id AND workspace_id=v_ctx.workspace_id;
   v_action:='Reprovou Testes';v_details:='Teste reprovado e retorno ao reparo registrado: '||v_reason;
 END IF;
 INSERT INTO public.ticket_logs(ticket_id,action,details,user_name)
 VALUES(v_ticket.id,v_action,v_details,v_ctx.actor_name);
 RETURN jsonb_build_object('success',true,'ticket_id',v_ticket.id,'status',p_status);
END $$;
REVOKE ALL ON FUNCTION public.conclude_ticket_test(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.conclude_ticket_test(uuid,text,jsonb) TO authenticated;


DROP POLICY "auth_notifications_delete" ON "public"."notifications";
DROP POLICY "auth_notifications_insert" ON "public"."notifications";
DROP POLICY "auth_notifications_read" ON "public"."notifications";
CREATE POLICY "auth_notifications_read" ON "public"."notifications" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS (SELECT 1 FROM public.tickets t WHERE t.id=notifications.ticket_id) AND EXISTS (SELECT 1 FROM public.get_current_actor_context() ctx WHERE (notifications.recipient_user_id IS NOT NULL AND notifications.recipient_user_id=COALESCE(ctx.actor_employee_id,ctx.actor_user_id)) OR (notifications.recipient_user_id IS NULL AND notifications.recipient_role=ANY(ctx.actor_roles)))));
DROP POLICY "auth_notifications_update" ON "public"."notifications";
CREATE POLICY "auth_notifications_update" ON "public"."notifications" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((EXISTS (SELECT 1 FROM public.tickets t WHERE t.id=notifications.ticket_id) AND EXISTS (SELECT 1 FROM public.get_current_actor_context() ctx WHERE (notifications.recipient_user_id IS NOT NULL AND notifications.recipient_user_id=COALESCE(ctx.actor_employee_id,ctx.actor_user_id)) OR (notifications.recipient_user_id IS NULL AND notifications.recipient_role=ANY(ctx.actor_roles))))) WITH CHECK ((EXISTS (SELECT 1 FROM public.tickets t WHERE t.id=notifications.ticket_id) AND EXISTS (SELECT 1 FROM public.get_current_actor_context() ctx WHERE (notifications.recipient_user_id IS NOT NULL AND notifications.recipient_user_id=COALESCE(ctx.actor_employee_id,ctx.actor_user_id)) OR (notifications.recipient_user_id IS NULL AND notifications.recipient_role=ANY(ctx.actor_roles)))));
DROP POLICY "ticket_logs_insert_by_role" ON "public"."ticket_logs";
CREATE POLICY "ticket_logs_insert_by_role" ON "public"."ticket_logs" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((((ticket_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM tickets t
  WHERE ((t.id = ticket_logs.ticket_id) AND (t.workspace_id = ( SELECT ctx.workspace_id
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) AND (( SELECT (ctx.is_admin OR ctx.is_attendant)
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) OR (( SELECT ctx.is_technician
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND ((t.technician_id = ( SELECT ctx.actor_employee_id
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) OR ((t.technician_id IS NULL) AND (t.status = ANY (ARRAY['Analise Tecnica'::text, 'Andamento Reparo'::text, 'Teste Final'::text]))))) OR (( SELECT ('tester'::text = ANY (COALESCE(ctx.actor_roles, '{}'::text[])))
           FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND (ticket_logs.action = ANY (ARRAY['Iniciou Testes'::text, 'Concluiu Testes'::text, 'Reprovou Testes'::text, 'Devolveu para Terceiro'::text])) AND (t.status = ANY (ARRAY['Teste Final'::text, 'Retirada Cliente'::text, 'Andamento Reparo'::text, 'Terceirizado'::text]))))))))) AND (CASE WHEN lower(translate(action,'çáàâãéêíóôõú','caaaaeeiooou')) IN ('excluiu chamado','restaurou chamado') THEN (SELECT ctx.is_admin FROM public.get_current_actor_context() ctx) WHEN lower(translate(action,'çáàâãéêíóôõú','caaaaeeiooou')) IN ('enviou orcamento','aprovou orcamento','negou orcamento','realizou compra','comprou pecas','recebeu pecas','retomou reparo apos compra') THEN (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx) ELSE true END));
DROP POLICY "tickets_select_by_role" ON "public"."tickets";
CREATE POLICY "tickets_select_by_role" ON "public"."tickets" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((((workspace_id = ( SELECT ctx.workspace_id
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) AND (( SELECT (ctx.is_admin OR ctx.is_attendant)
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) OR (( SELECT ctx.is_technician
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND ((technician_id = ( SELECT ctx.actor_employee_id
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant))) OR ((technician_id IS NULL) AND (status = ANY (ARRAY['Analise Tecnica'::text, 'Andamento Reparo'::text, 'Teste Final'::text]))))) OR (( SELECT ('tester'::text = ANY (COALESCE(ctx.actor_roles, '{}'::text[])))
   FROM get_current_actor_context() ctx(workspace_id, actor_user_id, actor_employee_id, actor_name, actor_roles, actor_kind, is_admin, is_technician, is_attendant)) AND (status = 'Teste Final'::text))))) AND (deleted_at IS NULL OR public.can_manage_workspace(workspace_id)));
DROP POLICY "auth_ticket_photos_insert" ON "storage"."objects";
CREATE POLICY "auth_ticket_photos_insert" ON "storage"."objects" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (bucket_id='ticket_photos' AND private.can_upload_ticket_photo(name));

REVOKE INSERT,UPDATE,DELETE ON public.notifications FROM authenticated;
DO $$ DECLARE r record;BEGIN
 FOR r IN SELECT attname FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attnum>0 AND NOT attisdropped LOOP
  EXECUTE format('REVOKE INSERT (%I),UPDATE (%I) ON public.notifications FROM authenticated',r.attname,r.attname);
 END LOOP;
END $$;
GRANT SELECT,UPDATE(is_read) ON public.notifications TO authenticated;
COMMIT;
