# Autenticação por Supabase e recuperação

## Estado de implantação

Este código requer a migração SQL incluída na branch e as três Edge Functions.
O convite pode ser criado e compartilhado por link sem serviço de e-mail. O envio
por SMTP será configurado quando o titular tiver seu domínio. A confirmação de
novas contas e a recuperação de senha ainda dependem de um envio de Auth funcional;
não desligar a confirmação para contornar essa dependência. O PostgreSQL local
não reproduz os serviços gerenciados do Supabase.

Projeto existente: `cpydazjwlmssbzzsurxu`. Fonte atual do GitHub Pages:
`fix/github-pages-landing-entry`. Aplicativo:
`https://oliverlleo.github.io/AIDA-GEST/app.html`.

## SMTP do domínio e configurações de Auth

1. Quando o domínio estiver disponível, configurar o remetente e autenticar o
   domínio conforme o provedor escolhido (SPF/DKIM/DMARC). Nenhum serviço pago é
   requisito desta implementação. Não há remetente nem credencial fictícia ativos.
2. No painel Supabase, configurar o SMTP do provedor, login e senha SMTP. A função
   de convites usa por padrão porta `465` com TLS; também aceita `2525`/`2587` com
   STARTTLS obrigatório. As Edge Functions [bloqueiam portas 25 e 587](https://supabase.com/docs/guides/functions/limits).
   O SMTP do Auth é configurado separadamente no painel e pode usar a porta
   oferecida pelo provedor. Inserir credenciais somente no painel/armazenamento
   de secrets, nunca no Git ou em mensagens do chat.
3. Manter confirmação de e-mail ligada. Definir Site URL como o endereço do
   aplicativo e permitir esse mesmo endereço e seus callbacks na lista de retorno.
   Não usar wildcard para domínios não controlados.
4. Modelo de confirmação: link para
   `{{ .SiteURL }}?auth=confirm&token_hash={{ .TokenHash }}&type=email`.
   Modelo de recuperação: link para
   `{{ .SiteURL }}?auth=recovery&token_hash={{ .TokenHash }}&type=recovery`.
   Manter os tokens fora de logs, screenshots e relatórios. Desligar rastreamento
   de cliques nos links de autenticação do provedor de e-mail.
   Os corpos completos preparados estão em `supabase/auth-templates/confirmation.html`
   e `supabase/auth-templates/recovery.html`; aplicar apenas junto com o frontend
   que reconhece esses callbacks. A lista de retorno deve permitir exatamente
   `https://oliverlleo.github.io/AIDA-GEST/app.html` e
   `https://oliverlleo.github.io/AIDA-GEST/app.html?**` para os parâmetros de callback
   e convite, sem abrir outros caminhos ou domínios.
5. Secrets das Edge Functions:
   - `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`: transporte autenticado.
   - `SMTP_SENDER_EMAIL`: remetente verificado do domínio.
   - `SMTP_SENDER_NAME`: nome visível, por padrão `CentralOS`.
   - `APP_URL`: endereço HTTPS exato do aplicativo acima, sem query ou fragmento.
   Os secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY` e
   `SUPABASE_SERVICE_ROLE_KEY` são fornecidos pelo Supabase. Não copiá-los ao frontend.
   `supabase/functions/SMTP-CONFIG.example` lista os campos vazios a preencher
   somente no armazenamento protegido quando o domínio estiver pronto.

## Convites e permissões

O cadastro público cria apenas a identidade. Criar empresa é uma ação explícita.
O convite da aplicação não pré-cria um usuário Auth: o destinatário entra ou
cria/confirma sua conta e aceita usando a mesma caixa de e-mail.

Convites têm validade de sete dias, não são credenciais e não concedem acesso
antes do aceite. São listados dentro do aplicativo e por link com referência
`app.html?invitation=UUID`. Falha no envio não desfaz o convite; o gestor pode
reenviar ou copiar o link. Resposta `queued` indica aceite pelo provedor, não
comprova recebimento. Tentativas concorrentes são reservadas atomicamente no banco.

Cada empresa valida suas próprias permissões. Bloquear/remover um funcionário
ou encerrar seu acesso em uma empresa não modifica sua senha nem sua conta Auth
global. O titular recupera a senha pelo fluxo de Auth. Mudanças de empresa e logout
recarregam a página para limpar dados e requisições da empresa anterior.

## Ordem de ativação

1. Conferir pacote de recuperação e a equivalência do baseline/restauração local.
2. Aprovar os testes SQL de permissões, migração e rollback e toda a suíte JS.
3. Validar criação/cópia/aceite de convites sem e-mail com identidades confirmadas.
   O SMTP e os testes reais de entrega ficam pendentes por escolha do titular.
   Antes de abrir cadastro/recuperação ao público, testar confirmação, recuperação
   e entrega com caixas controladas indicadas pelo titular. Não usar destinatários
   reais de terceiros como caixas de teste.
4. Aplicar a migração transacional no projeto existente, sem resetar schemas ou Auth.
5. Implantar as três Edge Functions com `verify_jwt=true`, incluindo os arquivos
   compartilhados, e verificar seu contexto por JWT/empresa. Elas também verificam
   a sessão junto ao Auth e a autorização no banco antes da operação.
6. Testar o frontend preparado com contas controladas: conta sem empresa, dono A
   e funcionário B, técnico/tester/atendente, convite expirado/cancelado, Storage,
   acompanhamento público e callbacks. Não tratar os testes locais como prova
   de funcionamento do SMTP ou da plataforma remota.
7. Atualizar a branch publicada apenas após os testes reais. Invalidar o cache
   dos scripts alterados e conferir desktop e celular no endereço publicado.

## Recuperação

O pacote externo de recuperação contém o histórico Git completo, o source ZIP
do commit publicado antes da migração, scripts CDN capturados, DDL do banco,
customizações de Storage/Auth, fontes/configuração das Edge Functions e manifesto.
Não contém dados de negócio, usuários Auth, arquivos de Storage ou senhas.

Para voltar no **mesmo projeto**, usar a migração reversa específica, restaurar
as fontes/configurações das Edge Functions e Auth registradas e publicar o commit
anterior do GitHub Pages. A reversa não deve apagar schemas gerenciados nem Auth.
O baseline serve para reconstrução estrutural em ambiente vazio, não substitui
a migração reversa num banco já populado.

Se o projeto for destruído, a estrutura poderá ser reconstruída, mas identidades,
vínculos, configurações de negócio e arquivos não copiados não serão recuperados.
Senhas/chaves necessárias ficam no armazenamento protegido do titular.
