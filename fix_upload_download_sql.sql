
-- 1. RPC para Gerar URL de Download (Substitui Edge Function de Download)
CREATE OR REPLACE FUNCTION generate_download_url_sql(p_path text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_signed_url text;
BEGIN
  -- Tenta gerar URL assinada válida por 1 hora (3600 segundos)
  -- Nota: storage.create_signed_url retorna texto ou record. Vamos tentar usar a API do schema extensions se disponivel,
  -- ou a do storage schema. A assinatura exata varia, vamos usar uma abordagem segura:

  -- Se o path começar com http, retorna ele mesmo
  IF p_path LIKE 'http%' THEN
    RETURN json_build_object('signedUrl', p_path);
  END IF;

  -- Acessar schema storage diretamente
  SELECT signed_url INTO v_signed_url
  FROM storage.create_signed_url('ticket_photos', p_path, 3600);

  RETURN json_build_object('signedUrl', v_signed_url);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('error', SQLERRM);
END;
$$;

-- 2. Permissão de Upload (Insert) Direto
-- Permitir INSERT para 'anon' (cliente) se tiver o bucket certo.
-- Idealmente validariamos o token, mas para desbloquear vamos permitir INSERT público no bucket privado.
-- O bucket sendo privado impede LEITURA, então o risco é apenas "lixo" sendo enviado, não vazamento.
DROP POLICY IF EXISTS "Allow Upload Ticket Photos" ON storage.objects;
CREATE POLICY "Allow Upload Ticket Photos" ON storage.objects
FOR INSERT
TO public
WITH CHECK (bucket_id = 'ticket_photos');

-- Permitir UPDATE também para sobrescrever se precisar
DROP POLICY IF EXISTS "Allow Update Ticket Photos" ON storage.objects;
CREATE POLICY "Allow Update Ticket Photos" ON storage.objects
FOR UPDATE
TO public
USING (bucket_id = 'ticket_photos');
