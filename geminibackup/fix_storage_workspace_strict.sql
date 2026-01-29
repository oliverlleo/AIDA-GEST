-- 1) Remover policies Strict por Ticket (que quebram upload pré-ticket)
DROP POLICY IF EXISTS "Strict Read Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Upload Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Update Access via Ticket" ON storage.objects;
DROP POLICY IF EXISTS "Strict Delete Access via Ticket" ON storage.objects;

-- 2) Remover policies genéricas (limpeza de segurança)
DROP POLICY IF EXISTS "Permitir Visualização de Fotos" ON storage.objects;
DROP POLICY IF EXISTS "Permitir Upload Seguro" ON storage.objects;
DROP POLICY IF EXISTS "Permitir Update Seguro" ON storage.objects;

-- 3) Limpar policies antigas de Employee Storage (para recriar corretamente)
DROP POLICY IF EXISTS "Employee Storage Select" ON storage.objects;
DROP POLICY IF EXISTS "Employee Storage Insert" ON storage.objects;
DROP POLICY IF EXISTS "Employee Storage Update" ON storage.objects;
DROP POLICY IF EXISTS "Employee Storage Delete" ON storage.objects;

-- 4) Criar policies "Strict por Workspace" (Employee)
-- Permite acesso se o primeiro segmento do path for o Workspace ID do funcionário logado.
-- Isso permite upload para folders de tickets que AINDA NÃO EXISTEM no banco,
-- desde que dentro do folder do workspace correto.

CREATE POLICY "Employee Storage Select"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] = (
    SELECT workspace_id::text FROM current_employee_from_token()
  )
);

CREATE POLICY "Employee Storage Insert"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] = (
    SELECT workspace_id::text FROM current_employee_from_token()
  )
);

CREATE POLICY "Employee Storage Update"
ON storage.objects FOR UPDATE
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] = (
    SELECT workspace_id::text FROM current_employee_from_token()
  )
)
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] = (
    SELECT workspace_id::text FROM current_employee_from_token()
  )
);

CREATE POLICY "Employee Storage Delete"
ON storage.objects FOR DELETE
TO anon, authenticated
USING (
  bucket_id = 'ticket_photos'
  AND (storage.foldername(name))[1] = (
    SELECT workspace_id::text FROM current_employee_from_token()
  )
);
