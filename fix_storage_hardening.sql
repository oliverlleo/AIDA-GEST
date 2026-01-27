-- Remove qualquer policy “genérica” que libera o bucket só por bucket_id
DROP POLICY IF EXISTS "Permitir Visualização de Fotos" ON storage.objects;
DROP POLICY IF EXISTS "Permitir Upload Seguro" ON storage.objects;
DROP POLICY IF EXISTS "Permitir Update Seguro" ON storage.objects;

-- Remove as versões antigas “Strict” se existirem (para recriar certo)
DROP POLICY IF EXISTS "Strict Read Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Upload Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Delete Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Update Access via Ticket" ON storage.objects;

CREATE POLICY "Strict Read Access via Ticket"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id = (storage.foldername(name))[1]::uuid
  )
);

CREATE POLICY "Strict Upload Access via Ticket"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id = (storage.foldername(name))[1]::uuid
  )
);

CREATE POLICY "Strict Delete Access via Ticket"
ON storage.objects FOR DELETE
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id = (storage.foldername(name))[1]::uuid
  )
);

-- UPDATE: ideal é NÃO precisar, mas se a API tentar mexer em metadata,
-- libera update somente se continuar no mesmo ticketId:
CREATE POLICY "Strict Update Access via Ticket"
ON storage.objects FOR UPDATE
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id = (storage.foldername(name))[1]::uuid
  )
)
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id = (storage.foldername(name))[1]::uuid
  )
);
