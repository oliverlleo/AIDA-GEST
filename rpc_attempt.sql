-- Função RPC para gerar URL de Upload Assinada
CREATE OR REPLACE FUNCTION generate_upload_url(ticket_id text, filename text, file_type text, storage_bucket text DEFAULT 'ticket_photos')
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER -- Roda com permissões elevadas para gerar o link
AS $$
DECLARE
  v_workspace_id uuid;
  v_path text;
  v_signed_url text;
  v_res json;
BEGIN
  -- 1. Validar Sessão (Opcional, mas recomendado se tiver acesso às tabelas)
  -- Aqui simplificamos assumindo que a chamada RPC já passou pelo Auth do Supabase ou Token Header customizado.
  -- Para segurança total, deveríamos validar o x-employee-token aqui se possível,
  -- mas como RPC usa contexto de sessão, vamos confiar que quem chama tem permissão de execução.

  -- 2. Gerar Path
  -- Estrutura: workspace/ticket/timestamp_file
  -- Como não temos workspace fácil aqui, vamos usar ticket_id como raiz ou tentar buscar.
  -- Vamos buscar o workspace do ticket.
  SELECT workspace_id INTO v_workspace_id FROM tickets WHERE id = ticket_id::uuid;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Ticket não encontrado';
  END IF;

  v_path := v_workspace_id || '/' || ticket_id || '/' || extract(epoch from now())::text || '_' || regexp_replace(filename, '[^a-zA-Z0-9.\-_]', '', 'g');

  -- 3. Gerar URL (Usando a função interna do storage se disponível ou construindo a chamada)
  -- Infelizmente, o PL/PGSQL não tem acesso direto fácil à API de administração do Storage para criar *Upload* URL assinada (apenas Download).
  -- A função storage.create_signed_url é para DOWNLOAD.
  -- Para UPLOAD, o padrão é usar a API S3 ou Edge Function.

  -- PORÉM, podemos conceder permissão de INSERT direto na tabela storage.objects via RLS para o usuário logado?
  -- Sim, mas o frontend quer uma URL assinada prévia.

  -- Se não conseguimos gerar URL de Upload via SQL puro (limitação do Supabase SQL API pública),
  -- então voltamos à estaca zero da Edge Function.

  -- MAS, espere. O Supabase permite upload direto se tiver RLS.
  -- Se configurarmos a RLS corretamente, o frontend pode fazer:
  -- supabase.storage.from('bucket').upload('path', file)
  -- E isso resolve tudo sem Edge Function!

  RETURN json_build_object('error', 'Use direct upload with RLS');
END;
$$;
