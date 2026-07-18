-- BACKUP / ROLLBACK DA ETAPA 2
-- Restaura as politicas e o modo das RPCs anteriores ao endurecimento por cargo.
-- Nao altera nem remove dados de OS, historicos, notas ou arquivos.

BEGIN;

DROP TRIGGER IF EXISTS aida_enforce_ticket_actor_identity ON public.tickets;
DROP FUNCTION IF EXISTS public.aida_enforce_ticket_actor_identity();
DROP TRIGGER IF EXISTS aida_set_internal_note_actor_identity ON public.internal_notes;
DROP FUNCTION IF EXISTS public.aida_set_internal_note_actor_identity();

DROP POLICY IF EXISTS tickets_select_by_role ON public.tickets;
DROP POLICY IF EXISTS tickets_insert_by_role ON public.tickets;
DROP POLICY IF EXISTS tickets_update_by_role ON public.tickets;
DROP POLICY IF EXISTS tickets_delete_admin_only ON public.tickets;

CREATE POLICY "Admin All Access"
ON public.tickets
AS PERMISSIVE
FOR ALL
TO authenticated
USING (workspace_id IN (SELECT workspaces.id FROM public.workspaces WHERE workspaces.owner_id = auth.uid()))
WITH CHECK (workspace_id IN (SELECT workspaces.id FROM public.workspaces WHERE workspaces.owner_id = auth.uid()));

CREATE POLICY "Tickets Access Policy"
ON public.tickets
AS PERMISSIVE
FOR ALL
TO anon, authenticated
USING (
    ((auth.role() = 'authenticated'::text) AND EXISTS (
        SELECT 1 FROM public.workspaces w
        WHERE w.id = tickets.workspace_id AND w.owner_id = auth.uid()
    ))
    OR workspace_id = (
        SELECT func.workspace_id FROM public.current_employee_from_token() func(employee_id, workspace_id, role)
    )
);

DROP POLICY IF EXISTS ticket_logs_select_by_role ON public.ticket_logs;
DROP POLICY IF EXISTS ticket_logs_insert_by_role ON public.ticket_logs;

CREATE POLICY "Secure Access Logs"
ON public.ticket_logs
AS PERMISSIVE
FOR ALL
TO anon, authenticated
USING (EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id = ticket_logs.ticket_id
      AND (
        ((auth.role() = 'authenticated'::text) AND EXISTS (
            SELECT 1 FROM public.workspaces w
            WHERE w.id = t.workspace_id AND w.owner_id = auth.uid()
        ))
        OR t.workspace_id = (
            SELECT current_employee_from_token.workspace_id
            FROM public.current_employee_from_token()
        )
      )
));

DROP POLICY IF EXISTS internal_notes_select_by_role ON public.internal_notes;
DROP POLICY IF EXISTS internal_notes_insert_by_role ON public.internal_notes;
DROP POLICY IF EXISTS internal_notes_update_by_role ON public.internal_notes;
DROP POLICY IF EXISTS internal_notes_delete_admin_only ON public.internal_notes;

CREATE POLICY "Secure Access Internal Notes"
ON public.internal_notes
AS PERMISSIVE
FOR ALL
TO anon, authenticated
USING (
    ((auth.role() = 'authenticated'::text) AND EXISTS (
        SELECT 1 FROM public.workspaces w
        WHERE w.id = internal_notes.workspace_id AND w.owner_id = auth.uid()
    ))
    OR workspace_id = (
        SELECT current_employee_from_token.workspace_id
        FROM public.current_employee_from_token()
    )
);

ALTER TABLE public.internal_notes NO FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS aida_ticket_photos_anon_select_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_anon_insert_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_anon_update_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_anon_delete_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_select_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_insert_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_update_by_role ON storage.objects;
DROP POLICY IF EXISTS aida_ticket_photos_auth_delete_by_role ON storage.objects;

DROP POLICY IF EXISTS fp_logos_anon_insert ON storage.objects;
DROP POLICY IF EXISTS fp_logos_anon_update ON storage.objects;
DROP POLICY IF EXISTS fp_logos_anon_delete ON storage.objects;
DROP POLICY IF EXISTS fp_logos_auth_insert ON storage.objects;
DROP POLICY IF EXISTS fp_logos_auth_update ON storage.objects;
DROP POLICY IF EXISTS fp_logos_auth_delete ON storage.objects;

CREATE POLICY fp_logos_anon_insert ON storage.objects
FOR INSERT TO anon
WITH CHECK (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY fp_logos_anon_update ON storage.objects
FOR UPDATE TO anon
USING (bucket_id = 'workspace_logos' AND public.can_manage_logo(name))
WITH CHECK (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY fp_logos_anon_delete ON storage.objects
FOR DELETE TO anon
USING (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY fp_logos_auth_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY fp_logos_auth_update ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY fp_logos_auth_delete ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'workspace_logos' AND public.can_manage_logo(name));

CREATE POLICY fp_ticket_photos_anon_select ON storage.objects
FOR SELECT TO anon
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (
        SELECT current_employee_from_token.workspace_id::text
        FROM public.current_employee_from_token()
    )
);

CREATE POLICY fp_ticket_photos_anon_insert ON storage.objects
FOR INSERT TO anon
WITH CHECK (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (
        SELECT current_employee_from_token.workspace_id::text
        FROM public.current_employee_from_token()
    )
);

CREATE POLICY fp_ticket_photos_anon_update ON storage.objects
FOR UPDATE TO anon
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (
        SELECT current_employee_from_token.workspace_id::text
        FROM public.current_employee_from_token()
    )
);

CREATE POLICY fp_ticket_photos_anon_delete ON storage.objects
FOR DELETE TO anon
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] = (
        SELECT current_employee_from_token.workspace_id::text
        FROM public.current_employee_from_token()
    )
);

CREATE POLICY fp_ticket_photos_auth_select ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] IN (
        SELECT profiles.workspace_id::text FROM public.profiles WHERE profiles.id = auth.uid()
    )
);

CREATE POLICY fp_ticket_photos_auth_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] IN (
        SELECT profiles.workspace_id::text FROM public.profiles WHERE profiles.id = auth.uid()
    )
);

CREATE POLICY fp_ticket_photos_auth_update ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] IN (
        SELECT profiles.workspace_id::text FROM public.profiles WHERE profiles.id = auth.uid()
    )
);

CREATE POLICY fp_ticket_photos_auth_delete ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'ticket_photos'
    AND (storage.foldername(name))[1] IN (
        SELECT profiles.workspace_id::text FROM public.profiles WHERE profiles.id = auth.uid()
    )
);

ALTER FUNCTION public.get_dashboard_kpis(date, date, uuid, text, text, text, text) SECURITY DEFINER;
ALTER FUNCTION public.get_daily_report(text, text) SECURITY DEFINER;
ALTER FUNCTION public.get_operational_queue(text, text, text, uuid, text, integer, integer) SECURITY DEFINER;

COMMIT;

