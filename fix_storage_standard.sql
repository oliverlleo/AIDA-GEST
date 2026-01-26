
-- 1. Limpar a RPC problemática
DROP FUNCTION IF EXISTS generate_download_url_sql;

-- 2. Limpar policies antigas de SELECT para evitar conflitos
DROP POLICY IF EXISTS "Permitir Visualização de Fotos" ON storage.objects;
DROP POLICY IF EXISTS "Public View" ON storage.objects;

-- 3. Criar Policy OFICIAL de Leitura para Authenticated
-- Isso permite que supabase.storage.from(...).createSignedUrl funcione
CREATE POLICY "Permitir Visualização de Fotos"
ON storage.objects FOR SELECT
TO authenticated
USING ( bucket_id = 'ticket_photos' );

-- Garantir que anon (cliente deslogado, se precisar ver via signed URL gerada por outro) não tenha acesso direto,
-- mas signed URLs funcionam porque a assinatura valida a permissão de quem CRIOU o link (service role ou user com acesso).
-- Como vamos criar o link no frontend com o usuário logado, o "TO authenticated" resolve a criação.
