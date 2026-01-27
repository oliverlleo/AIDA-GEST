-- 1) Remover policies Admin Storage* que assumem workspaceId na 1ª pasta (evita conflito)
DROP POLICY IF EXISTS "Admin Storage Insert" ON storage.objects;
DROP POLICY IF EXISTS "Admin Storage Select" ON storage.objects;
DROP POLICY IF EXISTS "Admin Storage Update" ON storage.objects;
DROP POLICY IF EXISTS "Admin Storage Delete" ON storage.objects;

-- 2) Remover Strict antigas (recriar tudo padronizado por ticketId)
DROP POLICY IF EXISTS "Strict Read Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Upload Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Update Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Delete Access via Ticket" ON storage.objects;

-- 3) Criar Strict READ (SELECT) via Ticket (herda RLS do tickets)
CREATE POLICY "Strict Read Access via Ticket"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id::text = (storage.foldername(objects.name))[1]
  )
);

-- 4) Criar Strict UPLOAD (INSERT) via Ticket
CREATE POLICY "Strict Upload Access via Ticket"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id::text = (storage.foldername(objects.name))[1]
  )
);

-- 5) Criar Strict UPDATE via Ticket (se algum fluxo precisar)
CREATE POLICY "Strict Update Access via Ticket"
ON storage.objects FOR UPDATE
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id::text = (storage.foldername(objects.name))[1]
  )
)
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id::text = (storage.foldername(objects.name))[1]
  )
);

-- 6) Criar Strict DELETE via Ticket
CREATE POLICY "Strict Delete Access via Ticket"
ON storage.objects FOR DELETE
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id::text = (storage.foldername(objects.name))[1]
  )
);
