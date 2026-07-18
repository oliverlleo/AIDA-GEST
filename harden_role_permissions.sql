-- ETAPA 2: autorizacao por cargo para OS, historicos, notas e fotos.
-- Mantem o isolamento por workspace e move as regras que antes existiam apenas
-- no front-end para o banco, onde nao podem ser contornadas pela Data API.

BEGIN;

-- ---------------------------------------------------------------------------
-- OS: leitura e escrita conforme o cargo e a atribuicao tecnica.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Admin All Access" ON public.tickets;
DROP POLICY IF EXISTS "Tickets Access Policy" ON public.tickets;
DROP POLICY IF EXISTS tickets_select_by_role ON public.tickets;
DROP POLICY IF EXISTS tickets_insert_by_role ON public.tickets;
DROP POLICY IF EXISTS tickets_update_by_role ON public.tickets;
DROP POLICY IF EXISTS tickets_delete_admin_only ON public.tickets;

CREATE POLICY tickets_select_by_role
ON public.tickets
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (
            (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
            AND (
                technician_id = (SELECT ctx.actor_employee_id FROM public.get_current_actor_context() ctx)
                OR (
                    technician_id IS NULL
                    AND status IN ('Analise Tecnica', 'Andamento Reparo', 'Teste Final')
                )
            )
        )
        OR (
            (SELECT 'tester' = ANY(COALESCE(ctx.actor_roles, '{}'::text[])) FROM public.get_current_actor_context() ctx)
            AND status = 'Teste Final'
        )
    )
);

CREATE POLICY tickets_insert_by_role
ON public.tickets
AS PERMISSIVE
FOR INSERT
TO anon, authenticated
WITH CHECK (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (
            (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
            AND technician_id = (SELECT ctx.actor_employee_id FROM public.get_current_actor_context() ctx)
        )
    )
);

CREATE POLICY tickets_update_by_role
ON public.tickets
AS PERMISSIVE
FOR UPDATE
TO anon, authenticated
USING (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (
            (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
            AND (
                technician_id = (SELECT ctx.actor_employee_id FROM public.get_current_actor_context() ctx)
                OR (
                    technician_id IS NULL
                    AND status IN ('Analise Tecnica', 'Andamento Reparo', 'Teste Final')
                )
            )
        )
        OR (
            (SELECT 'tester' = ANY(COALESCE(ctx.actor_roles, '{}'::text[])) FROM public.get_current_actor_context() ctx)
            AND status = 'Teste Final'
        )
    )
)
WITH CHECK (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (
            (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
            AND (
                technician_id = (SELECT ctx.actor_employee_id FROM public.get_current_actor_context() ctx)
                OR (
                    technician_id IS NULL
                    AND status IN ('Analise Tecnica', 'Andamento Reparo', 'Teste Final')
                )
            )
        )
        OR (
            (SELECT 'tester' = ANY(COALESCE(ctx.actor_roles, '{}'::text[])) FROM public.get_current_actor_context() ctx)
            AND status IN ('Teste Final', 'Retirada Cliente', 'Andamento Reparo', 'Terceirizado')
        )
    )
);

CREATE POLICY tickets_delete_admin_only
ON public.tickets
AS PERMISSIVE
FOR DELETE
TO anon, authenticated
USING (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (SELECT ctx.is_admin FROM public.get_current_actor_context() ctx)
);

CREATE OR REPLACE FUNCTION public.aida_enforce_ticket_actor_identity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
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
        RETURN NEW;
    END IF;

    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.public_token IS DISTINCT FROM OLD.public_token
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_by_name IS DISTINCT FROM OLD.created_by_name THEN
        RAISE EXCEPTION 'Acesso negado: campos de identidade da OS nao podem ser alterados.';
    END IF;

    IF NOT v_ctx.is_admin AND NOT v_ctx.is_attendant
       AND NEW.technician_id IS DISTINCT FROM OLD.technician_id THEN
        RAISE EXCEPTION 'Acesso negado: este cargo nao pode trocar o tecnico da OS.';
    END IF;

    -- O testador atua apenas no resultado do teste. Dados cadastrais, fotos,
    -- pecas, tecnico e demais campos da OS permanecem fora de sua permissao.
    IF NOT v_ctx.is_admin
       AND NOT v_ctx.is_attendant
       AND NOT v_ctx.is_technician
       AND 'tester' = ANY(COALESCE(v_ctx.actor_roles, '{}'::text[]))
       AND (
           to_jsonb(NEW) - ARRAY[
               'status', 'previous_status', 'test_start_at', 'test_notes',
               'deadline', 'priority', 'repair_start_at', 'updated_at',
               'outsourced_deadline', 'outsourced_return_count', 'outsourced_notes',
               'overview_queue_stage', 'overview_queue_entered_at'
           ]::text[]
       ) IS DISTINCT FROM (
           to_jsonb(OLD) - ARRAY[
               'status', 'previous_status', 'test_start_at', 'test_notes',
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

DROP TRIGGER IF EXISTS aida_enforce_ticket_actor_identity ON public.tickets;
CREATE TRIGGER aida_enforce_ticket_actor_identity
BEFORE INSERT OR UPDATE ON public.tickets
FOR EACH ROW EXECUTE FUNCTION public.aida_enforce_ticket_actor_identity();

-- ---------------------------------------------------------------------------
-- Historico: gerente/atendente leem; eventos sao anexados e nao reescritos.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Secure Access Logs" ON public.ticket_logs;
DROP POLICY IF EXISTS ticket_logs_select_by_role ON public.ticket_logs;
DROP POLICY IF EXISTS ticket_logs_insert_by_role ON public.ticket_logs;

CREATE POLICY ticket_logs_select_by_role
ON public.ticket_logs
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
    (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1
        FROM public.tickets t
        WHERE t.id = ticket_logs.ticket_id
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    )
);

CREATE POLICY ticket_logs_insert_by_role
ON public.ticket_logs
AS PERMISSIVE
FOR INSERT
TO anon, authenticated
WITH CHECK (
    ticket_id IS NOT NULL
    AND EXISTS (
        SELECT 1
        FROM public.tickets t
        WHERE t.id = ticket_logs.ticket_id
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
          AND (
              (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
              OR (
                  (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
                  AND (
                      t.technician_id = (SELECT ctx.actor_employee_id FROM public.get_current_actor_context() ctx)
                      OR (t.technician_id IS NULL AND t.status IN ('Analise Tecnica', 'Andamento Reparo', 'Teste Final'))
                  )
              )
              OR (
                  (SELECT 'tester' = ANY(COALESCE(ctx.actor_roles, '{}'::text[])) FROM public.get_current_actor_context() ctx)
                  AND ticket_logs.action IN ('Iniciou Testes', 'Concluiu Testes', 'Reprovou Testes', 'Devolveu para Terceiro')
                  AND t.status IN ('Teste Final', 'Retirada Cliente', 'Andamento Reparo', 'Terceirizado')
              )
          )
    )
);

-- Sem politicas UPDATE/DELETE: historico de auditoria e imutavel pela Data API.

-- ---------------------------------------------------------------------------
-- Notas: administrativas no workspace; tecnicas/testes apenas nas OS visiveis.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Secure Access Internal Notes" ON public.internal_notes;
DROP POLICY IF EXISTS internal_notes_select_by_role ON public.internal_notes;
DROP POLICY IF EXISTS internal_notes_insert_by_role ON public.internal_notes;
DROP POLICY IF EXISTS internal_notes_update_by_role ON public.internal_notes;
DROP POLICY IF EXISTS internal_notes_delete_admin_only ON public.internal_notes;

ALTER TABLE public.internal_notes FORCE ROW LEVEL SECURITY;

CREATE POLICY internal_notes_select_by_role
ON public.internal_notes
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (
            ticket_id IS NOT NULL
            AND EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = internal_notes.ticket_id)
        )
    )
);

CREATE POLICY internal_notes_insert_by_role
ON public.internal_notes
AS PERMISSIVE
FOR INSERT
TO anon, authenticated
WITH CHECK (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (
            ticket_id IS NOT NULL
            AND EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = internal_notes.ticket_id)
        )
    )
);

CREATE POLICY internal_notes_update_by_role
ON public.internal_notes
AS PERMISSIVE
FOR UPDATE
TO anon, authenticated
USING (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR author_id = (SELECT COALESCE(ctx.actor_employee_id, ctx.actor_user_id) FROM public.get_current_actor_context() ctx)
    )
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (ticket_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = internal_notes.ticket_id))
    )
)
WITH CHECK (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR author_id = (SELECT COALESCE(ctx.actor_employee_id, ctx.actor_user_id) FROM public.get_current_actor_context() ctx)
    )
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (ticket_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = internal_notes.ticket_id))
    )
);

CREATE POLICY internal_notes_delete_admin_only
ON public.internal_notes
AS PERMISSIVE
FOR DELETE
TO anon, authenticated
USING (
    workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    AND (SELECT ctx.is_admin FROM public.get_current_actor_context() ctx)
);

CREATE OR REPLACE FUNCTION public.aida_set_internal_note_actor_identity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ctx record;
BEGIN
    IF COALESCE(auth.role(), '') NOT IN ('anon', 'authenticated') THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_ctx FROM public.get_current_actor_context();

    IF TG_OP = 'INSERT' THEN
        NEW.workspace_id := v_ctx.workspace_id;
        NEW.author_id := COALESCE(v_ctx.actor_employee_id, v_ctx.actor_user_id);
        NEW.author_name := v_ctx.actor_name;
        RETURN NEW;
    END IF;

    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.ticket_id IS DISTINCT FROM OLD.ticket_id
       OR NEW.author_id IS DISTINCT FROM OLD.author_id
       OR NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Acesso negado: autoria e vinculo da nota nao podem ser alterados.';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS aida_set_internal_note_actor_identity ON public.internal_notes;
CREATE TRIGGER aida_set_internal_note_actor_identity
BEFORE INSERT OR UPDATE ON public.internal_notes
FOR EACH ROW EXECUTE FUNCTION public.aida_set_internal_note_actor_identity();

-- ---------------------------------------------------------------------------
-- Fotos privadas: o caminho workspace/OS precisa corresponder a uma OS visivel.
-- ---------------------------------------------------------------------------

-- As politicas antigas de logo chamavam uma funcao sem EXECUTE para anon. Como
-- todas as politicas INSERT do Storage entram na avaliacao, isso tambem podia
-- bloquear fotos. A mesma validacao fica inline, sem ampliar EXECUTE publico.
DROP POLICY IF EXISTS fp_logos_anon_insert ON storage.objects;
DROP POLICY IF EXISTS fp_logos_anon_update ON storage.objects;
DROP POLICY IF EXISTS fp_logos_anon_delete ON storage.objects;
DROP POLICY IF EXISTS fp_logos_auth_insert ON storage.objects;
DROP POLICY IF EXISTS fp_logos_auth_update ON storage.objects;
DROP POLICY IF EXISTS fp_logos_auth_delete ON storage.objects;

CREATE POLICY fp_logos_anon_insert ON storage.objects
FOR INSERT TO anon
WITH CHECK (
    bucket_id = 'workspace_logos'
    AND EXISTS (
        SELECT 1 FROM public.current_employee_from_token() ctx
        WHERE ctx.workspace_id::text = (storage.foldername(name))[1]
          AND 'admin' = ANY(COALESCE(ctx.role, '{}'::text[]))
    )
);

CREATE POLICY fp_logos_anon_update ON storage.objects
FOR UPDATE TO anon
USING (
    bucket_id = 'workspace_logos'
    AND EXISTS (
        SELECT 1 FROM public.current_employee_from_token() ctx
        WHERE ctx.workspace_id::text = (storage.foldername(name))[1]
          AND 'admin' = ANY(COALESCE(ctx.role, '{}'::text[]))
    )
)
WITH CHECK (
    bucket_id = 'workspace_logos'
    AND EXISTS (
        SELECT 1 FROM public.current_employee_from_token() ctx
        WHERE ctx.workspace_id::text = (storage.foldername(name))[1]
          AND 'admin' = ANY(COALESCE(ctx.role, '{}'::text[]))
    )
);

CREATE POLICY fp_logos_anon_delete ON storage.objects
FOR DELETE TO anon
USING (
    bucket_id = 'workspace_logos'
    AND EXISTS (
        SELECT 1 FROM public.current_employee_from_token() ctx
        WHERE ctx.workspace_id::text = (storage.foldername(name))[1]
          AND 'admin' = ANY(COALESCE(ctx.role, '{}'::text[]))
    )
);

CREATE POLICY fp_logos_auth_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'workspace_logos'
    AND (
        EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id::text = (storage.foldername(name))[1] AND w.owner_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.workspace_id::text = (storage.foldername(name))[1] AND p.role = 'admin')
    )
);

CREATE POLICY fp_logos_auth_update ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'workspace_logos'
    AND (
        EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id::text = (storage.foldername(name))[1] AND w.owner_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.workspace_id::text = (storage.foldername(name))[1] AND p.role = 'admin')
    )
)
WITH CHECK (
    bucket_id = 'workspace_logos'
    AND (
        EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id::text = (storage.foldername(name))[1] AND w.owner_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.workspace_id::text = (storage.foldername(name))[1] AND p.role = 'admin')
    )
);

CREATE POLICY fp_logos_auth_delete ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'workspace_logos'
    AND (
        EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id::text = (storage.foldername(name))[1] AND w.owner_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.workspace_id::text = (storage.foldername(name))[1] AND p.role = 'admin')
    )
);

DROP POLICY IF EXISTS fp_ticket_photos_anon_select ON storage.objects;
DROP POLICY IF EXISTS fp_ticket_photos_anon_insert ON storage.objects;
DROP POLICY IF EXISTS fp_ticket_photos_anon_update ON storage.objects;
DROP POLICY IF EXISTS fp_ticket_photos_anon_delete ON storage.objects;
DROP POLICY IF EXISTS fp_ticket_photos_auth_select ON storage.objects;
DROP POLICY IF EXISTS fp_ticket_photos_auth_insert ON storage.objects;
DROP POLICY IF EXISTS fp_ticket_photos_auth_update ON storage.objects;
DROP POLICY IF EXISTS fp_ticket_photos_auth_delete ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_anon_select_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_anon_insert_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_anon_update_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_anon_delete_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_select_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_insert_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_update_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_delete_by_role ON storage.objects;

CREATE POLICY aida_ticket_photos_anon_select_by_role ON storage.objects
FOR SELECT TO anon
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    )
);

CREATE POLICY aida_ticket_photos_anon_insert_by_role ON storage.objects
FOR INSERT TO anon
WITH CHECK (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND COALESCE((storage.foldername(name))[2], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND (
        (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
        OR (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
    )
);

CREATE POLICY aida_ticket_photos_anon_update_by_role ON storage.objects
FOR UPDATE TO anon
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
          AND (
              (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
              OR (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
          )
    )
)
WITH CHECK (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
          AND (
              (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
              OR (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
          )
    )
);

CREATE POLICY aida_ticket_photos_anon_delete_by_role ON storage.objects
FOR DELETE TO anon
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
          AND (
              (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
              OR (SELECT ctx.is_technician FROM public.get_current_actor_context() ctx)
          )
    )
);

CREATE POLICY aida_ticket_photos_auth_select_by_role ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    )
);

CREATE POLICY aida_ticket_photos_auth_insert_by_role ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND COALESCE((storage.foldername(name))[2], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
);

CREATE POLICY aida_ticket_photos_auth_update_by_role ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    )
)
WITH CHECK (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    )
);

CREATE POLICY aida_ticket_photos_auth_delete_by_role ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (SELECT ctx.workspace_id::text FROM public.get_current_actor_context() ctx)
    AND (SELECT ctx.is_admin OR ctx.is_attendant FROM public.get_current_actor_context() ctx)
    AND EXISTS (
        SELECT 1 FROM public.tickets t
        WHERE t.id::text = (storage.foldername(name))[2]
          AND t.workspace_id = (SELECT ctx.workspace_id FROM public.get_current_actor_context() ctx)
    )
);

-- RPCs de consulta de OS passam a respeitar as mesmas politicas RLS.
ALTER FUNCTION public.get_dashboard_kpis(date, date, uuid, text, text, text, text) SECURITY INVOKER;
ALTER FUNCTION public.get_daily_report(text, text) SECURITY INVOKER;
ALTER FUNCTION public.get_operational_queue(text, text, text, uuid, text, integer, integer) SECURITY INVOKER;

COMMIT;
