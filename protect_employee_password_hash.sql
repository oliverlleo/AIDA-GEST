-- ETAPA 1: impedir leitura de password_hash pela Data API.
-- Nenhum dado e nenhuma senha sao alterados.

BEGIN;

-- SELECT concedido na tabela inteira prevalece sobre permissoes de coluna.
-- Por isso ele precisa ser removido antes da lista segura ser concedida.
REVOKE SELECT ON TABLE public.employees FROM anon, authenticated;

GRANT SELECT (
    id,
    workspace_id,
    name,
    username,
    roles,
    created_at,
    deleted_at,
    must_change_password
) ON TABLE public.employees TO anon, authenticated;

-- Funcoes SECURITY DEFINER de login e administracao continuam acessando o hash
-- internamente com os privilegios do proprietario, sem devolve-lo ao cliente.

NOTIFY pgrst, 'reload schema';

COMMIT;
