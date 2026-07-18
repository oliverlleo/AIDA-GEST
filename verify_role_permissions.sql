-- TESTE TRANSACIONAL DA ETAPA 2
-- Cria identidades e registros sinteticos, valida a matriz de cargos e executa
-- ROLLBACK no final. Nenhum registro de teste permanece no banco.

BEGIN;

DO $setup$
DECLARE
    v_workspace uuid;
    v_other_workspace uuid;
BEGIN
    SELECT t.workspace_id INTO v_workspace
    FROM public.tickets t
    WHERE t.deleted_at IS NULL
    ORDER BY t.created_at
    LIMIT 1;

    SELECT t.workspace_id INTO v_other_workspace
    FROM public.tickets t
    WHERE t.workspace_id IS DISTINCT FROM v_workspace
      AND t.deleted_at IS NULL
    ORDER BY t.created_at
    LIMIT 1;

    IF v_workspace IS NULL OR v_other_workspace IS NULL THEN
        RAISE EXCEPTION 'O teste requer duas empresas com ao menos uma OS.';
    END IF;

    INSERT INTO public.employees (id, workspace_id, name, username, password_hash, roles)
    VALUES
      ('30000000-0000-4000-8000-000000000001', v_workspace, 'Teste Tecnico Etapa 2', '__aida_test_tech__', 'test-only', ARRAY['tecnico']),
      ('30000000-0000-4000-8000-000000000002', v_workspace, 'Teste Atendente Etapa 2', '__aida_test_attendant__', 'test-only', ARRAY['atendente']),
      ('30000000-0000-4000-8000-000000000003', v_workspace, 'Teste Admin Etapa 2', '__aida_test_admin__', 'test-only', ARRAY['admin']),
      ('30000000-0000-4000-8000-000000000004', v_workspace, 'Teste Qualidade Etapa 2', '__aida_test_tester__', 'test-only', ARRAY['tester']);

    INSERT INTO public.employee_sessions (employee_id, expires_at, token)
    VALUES
      ('30000000-0000-4000-8000-000000000001', now() + interval '1 hour', '40000000-0000-4000-8000-000000000001'),
      ('30000000-0000-4000-8000-000000000002', now() + interval '1 hour', '40000000-0000-4000-8000-000000000002'),
      ('30000000-0000-4000-8000-000000000003', now() + interval '1 hour', '40000000-0000-4000-8000-000000000003'),
      ('30000000-0000-4000-8000-000000000004', now() + interval '1 hour', '40000000-0000-4000-8000-000000000004');

    INSERT INTO public.tickets
    SELECT (jsonb_populate_record(
        NULL::public.tickets,
        to_jsonb(src) || jsonb_build_object(
            'id', '20000000-0000-4000-8000-000000000001',
            'public_token', gen_random_uuid(),
            'os_number', '__AIDA_ROLE_OWN__',
            'technician_id', '30000000-0000-4000-8000-000000000001',
            'status', 'Analise Tecnica',
            'defect_reported', 'Defeito sintetico',
            'analysis_deadline', now() + interval '1 day',
            'deadline', now() + interval '2 days',
            'analysis_started_at', NULL,
            'repair_start_at', NULL,
            'test_start_at', NULL,
            'deleted_at', NULL,
            'delivered_at', NULL,
            'created_at', now(),
            'updated_at', now()
        )
    )).*
    FROM (SELECT * FROM public.tickets WHERE workspace_id = v_workspace LIMIT 1) src;

    INSERT INTO public.tickets
    SELECT (jsonb_populate_record(
        NULL::public.tickets,
        to_jsonb(src) || jsonb_build_object(
            'id', '20000000-0000-4000-8000-000000000002',
            'public_token', gen_random_uuid(),
            'os_number', '__AIDA_ROLE_OTHER__',
            'technician_id', '30000000-0000-4000-8000-000000000003',
            'status', 'Analise Tecnica',
            'defect_reported', 'Defeito sintetico',
            'analysis_deadline', now() + interval '1 day',
            'deadline', now() + interval '2 days',
            'analysis_started_at', NULL,
            'repair_start_at', NULL,
            'test_start_at', NULL,
            'deleted_at', NULL,
            'delivered_at', NULL,
            'created_at', now(),
            'updated_at', now()
        )
    )).*
    FROM (SELECT * FROM public.tickets WHERE workspace_id = v_workspace LIMIT 1) src;

    INSERT INTO public.tickets
    SELECT (jsonb_populate_record(
        NULL::public.tickets,
        to_jsonb(src) || jsonb_build_object(
            'id', '20000000-0000-4000-8000-000000000003',
            'public_token', gen_random_uuid(),
            'os_number', '__AIDA_ROLE_UNASSIGNED__',
            'technician_id', '30000000-0000-4000-8000-000000000001',
            'status', 'Andamento Reparo',
            'defect_reported', 'Defeito sintetico',
            'analysis_deadline', now() + interval '1 day',
            'deadline', now() + interval '2 days',
            'analysis_started_at', now(),
            'repair_start_at', NULL,
            'test_start_at', NULL,
            'deleted_at', NULL,
            'delivered_at', NULL,
            'created_at', now(),
            'updated_at', now()
        )
    )).*
    FROM (SELECT * FROM public.tickets WHERE workspace_id = v_workspace LIMIT 1) src;

    INSERT INTO public.tickets
    SELECT (jsonb_populate_record(
        NULL::public.tickets,
        to_jsonb(src) || jsonb_build_object(
            'id', '20000000-0000-4000-8000-000000000004',
            'public_token', gen_random_uuid(),
            'os_number', '__AIDA_ROLE_TEST__',
            'technician_id', '30000000-0000-4000-8000-000000000003',
            'status', 'Teste Final',
            'defect_reported', 'Defeito sintetico',
            'analysis_deadline', now() + interval '1 day',
            'deadline', now() + interval '2 days',
            'test_start_at', NULL,
            'deleted_at', NULL,
            'delivered_at', NULL,
            'created_at', now(),
            'updated_at', now()
        )
    )).*
    FROM (SELECT * FROM public.tickets WHERE workspace_id = v_workspace LIMIT 1) src;

    INSERT INTO public.tickets
    SELECT (jsonb_populate_record(
        NULL::public.tickets,
        to_jsonb(src) || jsonb_build_object(
            'id', '20000000-0000-4000-8000-000000000005',
            'public_token', gen_random_uuid(),
            'os_number', '__AIDA_ROLE_CROSS_WORKSPACE__',
            'defect_reported', 'Defeito sintetico',
            'analysis_deadline', now() + interval '1 day',
            'deadline', now() + interval '2 days',
            'deleted_at', NULL,
            'delivered_at', NULL,
            'created_at', now(),
            'updated_at', now()
        )
    )).*
    FROM (SELECT * FROM public.tickets WHERE workspace_id = v_other_workspace LIMIT 1) src;

    INSERT INTO storage.objects (id, bucket_id, name)
    VALUES
      ('50000000-0000-4000-8000-000000000001', 'ticket_photos', v_workspace::text || '/20000000-0000-4000-8000-000000000001/own.jpg'),
      ('50000000-0000-4000-8000-000000000002', 'ticket_photos', v_workspace::text || '/20000000-0000-4000-8000-000000000002/other.jpg'),
      ('50000000-0000-4000-8000-000000000003', 'ticket_photos', v_workspace::text || '/20000000-0000-4000-8000-000000000004/test.jpg');
END;
$setup$;

-- Tecnico: somente OS atribuidas a ele; demais ficam invisiveis.
SELECT set_config('request.headers', '{"x-employee-token":"40000000-0000-4000-8000-000000000001"}', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SET LOCAL ROLE anon;
DO $tech$
DECLARE
    v_rows integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tickets WHERE id = '20000000-0000-4000-8000-000000000001') THEN
        RAISE EXCEPTION 'Tecnico nao visualizou a propria OS.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.tickets WHERE id = '20000000-0000-4000-8000-000000000003') THEN
        RAISE EXCEPTION 'Tecnico nao visualizou a segunda OS atribuida.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.tickets WHERE id IN ('20000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000005')) THEN
        RAISE EXCEPTION 'Tecnico visualizou OS fora da permissao.';
    END IF;

    UPDATE public.tickets SET tech_notes = 'teste permitido', updated_at = now()
    WHERE id = '20000000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN RAISE EXCEPTION 'Tecnico nao conseguiu atualizar a propria OS.'; END IF;

    UPDATE public.tickets SET tech_notes = 'nao permitido', updated_at = now()
    WHERE id = '20000000-0000-4000-8000-000000000002';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 0 THEN RAISE EXCEPTION 'Tecnico atualizou OS de outro responsavel.'; END IF;

    BEGIN
        UPDATE public.tickets
        SET technician_id = '30000000-0000-4000-8000-000000000003', updated_at = now()
        WHERE id = '20000000-0000-4000-8000-000000000001';
        RAISE EXCEPTION 'Tecnico conseguiu trocar o responsavel da OS.';
    EXCEPTION WHEN insufficient_privilege OR check_violation OR raise_exception THEN
        IF SQLERRM = 'Tecnico conseguiu trocar o responsavel da OS.' THEN RAISE; END IF;
    END;

    INSERT INTO public.ticket_logs (id, ticket_id, action, details, user_name)
    VALUES ('60000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Teste de Permissao', 'registro sintetico', 'Nome Forjado');

    IF EXISTS (SELECT 1 FROM public.ticket_logs WHERE id = '60000000-0000-4000-8000-000000000001') THEN
        RAISE EXCEPTION 'Tecnico conseguiu ler o historico administrativo.';
    END IF;

    INSERT INTO public.internal_notes (id, workspace_id, ticket_id, author_id, author_name, content)
    VALUES (
      '70000000-0000-4000-8000-000000000001', gen_random_uuid(),
      '20000000-0000-4000-8000-000000000001', gen_random_uuid(), 'Nome Forjado', 'nota sintetica'
    );

    BEGIN
        INSERT INTO public.internal_notes (workspace_id, author_id, author_name, content)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'Nome Forjado', 'nota geral indevida');
        RAISE EXCEPTION 'Tecnico conseguiu criar nota geral.';
    EXCEPTION WHEN insufficient_privilege OR check_violation OR raise_exception THEN
        IF SQLERRM = 'Tecnico conseguiu criar nota geral.' THEN RAISE; END IF;
    END;

    IF (SELECT count(*) FROM storage.objects WHERE id IN (
        '50000000-0000-4000-8000-000000000001',
        '50000000-0000-4000-8000-000000000002'
    )) <> 1 THEN
        RAISE EXCEPTION 'Filtro de fotos do tecnico nao corresponde a OS visivel.';
    END IF;

    INSERT INTO storage.objects (id, bucket_id, name)
    VALUES (
      '50000000-0000-4000-8000-000000000004', 'ticket_photos',
      (SELECT workspace_id::text FROM public.get_current_actor_context()) || '/90000000-0000-4000-8000-000000000001/new.jpg'
    );
END;
$tech$;
RESET ROLE;

-- Atendente: acesso administrativo do workspace, nunca a outra empresa.
SELECT set_config('request.headers', '{"x-employee-token":"40000000-0000-4000-8000-000000000002"}', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SET LOCAL ROLE anon;
DO $attendant$
DECLARE
    v_rows integer;
BEGIN
    IF (SELECT count(*) FROM public.tickets WHERE id IN (
        '20000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000002',
        '20000000-0000-4000-8000-000000000003',
        '20000000-0000-4000-8000-000000000004'
    )) <> 4 THEN
        RAISE EXCEPTION 'Atendente nao visualizou as OS administrativas do workspace.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.tickets WHERE id = '20000000-0000-4000-8000-000000000005') THEN
        RAISE EXCEPTION 'Atendente visualizou OS de outra empresa.';
    END IF;

    UPDATE public.tickets SET tech_notes = 'teste atendente', updated_at = now()
    WHERE id = '20000000-0000-4000-8000-000000000002';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN RAISE EXCEPTION 'Atendente nao conseguiu atualizar OS administrativa.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM public.ticket_logs WHERE id = '60000000-0000-4000-8000-000000000001') THEN
        RAISE EXCEPTION 'Atendente nao conseguiu visualizar historico.';
    END IF;

    INSERT INTO public.internal_notes (id, workspace_id, author_id, author_name, content)
    VALUES ('70000000-0000-4000-8000-000000000002', gen_random_uuid(), gen_random_uuid(), 'Nome Forjado', 'nota geral sintetica');

    IF (SELECT count(*) FROM storage.objects WHERE id IN (
        '50000000-0000-4000-8000-000000000001',
        '50000000-0000-4000-8000-000000000002'
    )) <> 2 THEN
        RAISE EXCEPTION 'Atendente nao visualizou as fotos administrativas.';
    END IF;

    PERFORM public.get_dashboard_kpis(NULL::date, NULL::date, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text);
    PERFORM public.get_operational_queue(
        'all'::text, 'auto'::text, NULL::text, NULL::uuid,
        NULL::text, 50::integer, 0::integer
    );
END;
$attendant$;
RESET ROLE;

-- Testador: apenas OS em Teste Final, sem alterar cadastro ou enviar fotos.
SELECT set_config('request.headers', '{"x-employee-token":"40000000-0000-4000-8000-000000000004"}', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SET LOCAL ROLE anon;
DO $tester$
DECLARE
    v_rows integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tickets WHERE id = '20000000-0000-4000-8000-000000000004')
       OR EXISTS (SELECT 1 FROM public.tickets WHERE id = '20000000-0000-4000-8000-000000000001') THEN
        RAISE EXCEPTION 'Visibilidade do testador esta incorreta.';
    END IF;

    UPDATE public.tickets SET test_start_at = now(), updated_at = now()
    WHERE id = '20000000-0000-4000-8000-000000000004';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN RAISE EXCEPTION 'Testador nao conseguiu iniciar o teste.'; END IF;

    BEGIN
        UPDATE public.tickets SET client_name = 'alteracao indevida', updated_at = now()
        WHERE id = '20000000-0000-4000-8000-000000000004';
        RAISE EXCEPTION 'Testador conseguiu alterar o cadastro da OS.';
    EXCEPTION WHEN insufficient_privilege OR check_violation OR raise_exception THEN
        IF SQLERRM = 'Testador conseguiu alterar o cadastro da OS.' THEN RAISE; END IF;
    END;

    IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE id = '50000000-0000-4000-8000-000000000003') THEN
        RAISE EXCEPTION 'Testador nao conseguiu visualizar foto da OS em teste.';
    END IF;

    BEGIN
        INSERT INTO storage.objects (id, bucket_id, name)
        VALUES (
          '50000000-0000-4000-8000-000000000005', 'ticket_photos',
          (SELECT workspace_id::text FROM public.get_current_actor_context()) || '/20000000-0000-4000-8000-000000000004/tester-upload.jpg'
        );
        RAISE EXCEPTION 'Testador conseguiu enviar foto.';
    EXCEPTION WHEN insufficient_privilege OR check_violation OR raise_exception THEN
        IF SQLERRM = 'Testador conseguiu enviar foto.' THEN RAISE; END IF;
    END;
END;
$tester$;
RESET ROLE;

-- Administrador funcionario: relatorio existente continua executando.
SELECT set_config('request.headers', '{"x-employee-token":"40000000-0000-4000-8000-000000000003"}', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SET LOCAL ROLE anon;
DO $admin$
BEGIN
    PERFORM public.get_daily_report(NULL::text, NULL::text);
END;
$admin$;
RESET ROLE;

-- Identidade e autoria sempre sao definidas pelo servidor.
DO $identity$
BEGIN
    IF (SELECT user_name FROM public.ticket_logs WHERE id = '60000000-0000-4000-8000-000000000001') <> 'Teste Tecnico Etapa 2' THEN
        RAISE EXCEPTION 'Historico aceitou nome enviado pelo navegador.';
    END IF;
    IF (SELECT author_id FROM public.internal_notes WHERE id = '70000000-0000-4000-8000-000000000001') <> '30000000-0000-4000-8000-000000000001' THEN
        RAISE EXCEPTION 'Nota tecnica aceitou autoria enviada pelo navegador.';
    END IF;
    IF (SELECT author_id FROM public.internal_notes WHERE id = '70000000-0000-4000-8000-000000000002') <> '30000000-0000-4000-8000-000000000002' THEN
        RAISE EXCEPTION 'Nota administrativa aceitou autoria enviada pelo navegador.';
    END IF;
END;
$identity$;

ROLLBACK;
SELECT 'role_permissions_verified_without_persisting_test_data' AS result;
