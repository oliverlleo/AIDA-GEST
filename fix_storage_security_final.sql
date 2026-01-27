-- 1. Remover as regras antigas e inseguras (Públicas)
DROP POLICY IF EXISTS "Allow Upload Ticket Photos" ON storage.objects;
DROP POLICY IF EXISTS "Allow Update Ticket Photos" ON storage.objects;

-- 2. Criar regra de Upload BLINDADA (Só usuários logados)
CREATE POLICY "Permitir Upload Seguro"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'ticket_photos' );

-- 3. (Opcional) Se precisar de Update, restringe também
CREATE POLICY "Permitir Update Seguro"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'ticket_photos' );
