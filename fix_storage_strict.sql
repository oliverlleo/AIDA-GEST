
-- 1. Remover políticas antigas ou permissivas
DROP POLICY IF EXISTS "Permitir Visualização de Fotos" ON storage.objects;
DROP POLICY IF EXISTS "Permitir Upload Seguro" ON storage.objects;
DROP POLICY IF EXISTS "Permitir Update Seguro" ON storage.objects;
DROP POLICY IF EXISTS "Allow Upload Ticket Photos" ON storage.objects;
DROP POLICY IF EXISTS "Allow Update Ticket Photos" ON storage.objects;
DROP POLICY IF EXISTS "Strict Read Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Upload Access via Ticket" ON storage.objects;

-- 2. LEITURA ESTRITA: Permite se o usuário tem acesso ao ticket
-- Valida se a pasta (primeira parte do path) é um ID de ticket acessível na tabela 'tickets'
-- Nota: Para funcionar com 'TO public', a validação depende da tabela 'tickets' ter RLS que verifica o token atual.
CREATE POLICY "Strict Read Access via Ticket"
ON storage.objects FOR SELECT
TO public
USING (
  bucket_id = 'ticket_photos'
  AND (
    (storage.foldername(name))[1]::uuid IN (SELECT id FROM tickets)
  )
);

-- 3. UPLOAD ESTRITO: Permite se o usuário tem acesso ao ticket
-- O usuário deve ter permissão de VER o ticket (SELECT id FROM tickets) para poder subir foto para ele.
CREATE POLICY "Strict Upload Access via Ticket"
ON storage.objects FOR INSERT
TO public
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND (
    (storage.foldername(name))[1]::uuid IN (SELECT id FROM tickets)
  )
);

-- 4. DELETE ESTRITO (Manter consistência)
CREATE POLICY "Strict Delete Access via Ticket"
ON storage.objects FOR DELETE
TO public
USING (
  bucket_id = 'ticket_photos'
  AND (
    (storage.foldername(name))[1]::uuid IN (SELECT id FROM tickets)
  )
);
