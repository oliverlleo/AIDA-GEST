# Contenção de abuso de requisições

Migração publicada: `20261016020611_advanced_abuse_protection.sql`. O arquivo foi inicialmente criado pela CLI como `20261015222623_advanced_abuse_protection.sql`; o conteúdo testado foi preservado e o nome alinhado à versão registrada pelo Supabase.

## Limites

| Caminho | Contenção no servidor |
| --- | --- |
| Transações via PostgREST | Até 48 simultâneas no projeto, 24 por conta e 12 anônimas, com advisory locks transacionais. O pool do provedor pode impor teto menor. |
| Transações de escrita via PostgREST | Por conta: 120 por janela fixa de 10 segundos e 600 por minuto. RPCs VOLATILE também contam, mesmo que façam leitura. GET/HEAD e RPCs STABLE/IMMUTABLE preservam modo somente leitura e usam apenas contenção de concorrência. |
| Equipe e convites | 60/minuto e 300/hora por conta e empresa verificada. Mantém a autorização original. |
| Edge: logo ou convite | Orçamentos separados de 30/minuto e 300/hora por conta e empresa. O alias quick-api compartilha o orçamento de logo. Consumo confirma em RPC própria antes do trabalho. |
| Novos caminhos de upload | Reservas autenticadas com validade de 15 minutos, até 120/minuto e 2.000/hora por conta. A reserva não concede privilégios sobre a OS ou empresa. |
| Acompanhamento público | POST; 1.800/minuto e 9.000/hora globalmente, mais 120/minuto por grupo de hash da OS. Usa 1.024 grupos para limitar a cardinalidade dos contadores. Wrapper e função base contam uma vez por transação. |

HTTP 429 informa `Retry-After`. O aplicativo não repete escritas automaticamente. Abas antigas devem ser recarregadas após a publicação, pois uploads novos passam a exigir uma reserva.

Fotos aceitam imagens de até 20 MB, incluindo HEIC/HEIF; logos até 5 MB em JPEG/PNG/WebP/GIF; inventário permanece com 5 MB em JPEG/PNG/WebP. O limite real é aplicado na configuração do bucket. Foram alteradas somente as colunas de configuração `file_size_limit` e `allowed_mime_types`, com verificação dos valores anteriores. Objetos Storage, conteúdo e flags públicos não são modificados.

Foram fechados três casos de paginação NULL e limitado/deduplicado o array de locais do estoque. `p_limit=0` continua válido nos contadores que já o aceitam.

## Publicação e recuperação

1. Preservar código, histórico Git, definições/ACLs/policies/configurações e código das Edge Functions; nenhum dado de negócio é necessário.
2. Aplicar a migração. Reservas começam opcionais, permitindo publicar os clientes de forma ordenada.
3. Publicar as três Edge Functions e o frontend; verificar os arquivos efetivamente servidos.
4. Ativar `private.abuse_settings.storage_reservation_required` somente após a publicação compatível.

Para reverter: primeiro desligar a exigência de reserva; restaurar o frontend e as Edge Functions da versão anterior; aplicar `supabase/rollback_advanced_abuse_protection.sql`. O rollback restaura as configurações dos buckets, as funções anteriores e a configuração do hook, removendo apenas tabelas e funções novas de controle. Não remove registros de negócio ou arquivos. O pacote local de recuperação contém as versões anteriores e checksums; não inclui contas Auth, credenciais ou dados operacionais.

## Validação e alcance

Há 200 testes JavaScript, 31 etapas SQL incluindo regressão e rollback com 14 grupos de metadados, e 52 verificações HTTP locais com COMMIT. O carregamento com serviços reais e rede simulada chegou a 20 chamadas simultâneas em duas abas de kanban; o teto por conta foi definido acima desse pico.

Os testes SQL/HTTP usam somente identidades e registros sintéticos. O runtime portátil alinha explicitamente a propriedade de funções a `postgres`, como na produção; permissões de helpers internos não são abertas para contornar diferenças do ambiente.

Contadores da mesma transação não persistem quando a operação é revertida. Reservas limitam novos caminhos, não toda transmissão ou replay de sobrescritas. Concorrência de transações não limita filas antes de chegar ao banco. Proteção volumétrica depende da infraestrutura Cloudflare/Supabase. Auth conserva seus limites próprios; CAPTCHA, SMTP e regras personalizadas de WAF não são ativados por esta migração. GraphQL não foi revogado; a arquitetura oficial o encaminha ao PostgREST. Storage/Auth/Realtime não recebem o hook REST e têm controles próprios.

Não houve teste de carga em produção. Fluxos com conta real de proprietário não foram exercitados nesta etapa; a verificação funcional autenticada ocorreu no ambiente local sintético e foi comparada à estrutura implantada.
