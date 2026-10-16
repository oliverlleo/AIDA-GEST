# Concorrência e sincronização entre computadores

O banco é a autoridade para permissões, estados e versões. Ocultar um botão ou impedir duplo clique no navegador não substitui essas validações.

## Gravações

`tickets.revision` avança no servidor em toda alteração. PATCH/DELETE com sessão Auth exigem `x-aida-ticket-version` com `{id,revision}`; uma versão antiga, inválida ou ausente recebe HTTP 409. O trigger compara a linha bloqueada, impedindo que dois computadores salvem o mesmo snapshot. O navegador não pode atribuir sua própria revisão. Comandos transacionais existentes mantêm seus locks e verificações de estado, com uma lista explícita de rotas permitidas para alterações internas.

Compras e agendamentos possuem revisão própria. Recebimento parcial de compra e remarcação exigem `x-aida-operation-version` com `{resource,id,revision}`. Se uma segunda solicitação parte do mesmo formulário antigo, a transação inteira é recusada, incluindo estoque, movimentos e logs derivados.

Criar agendamento, solicitar peças e aprovar com estoque retornam `ticket_id`, `ticket_revision` e `ticket_updates` com campos operacionais permitidos. A revisão original é validada antes do comando. As etapas seguintes usam somente esse recibo da própria transação; não adotam um GET recente para promover um rascunho antigo.

Checklists de notas usam um comando autenticado com RLS para mudar somente um item sob lock, com estado desejado explícito. Dois itens diferentes são preservados; repetir a mesma marcação não desmarca o item.

Não há repetição automática de gravações. Um timeout avisa que o resultado pode ser incerto e orienta consultar o estado antes de repetir. Falha de refresh ou de histórico após um commit confirmado não é apresentada como falha da gravação inteira. Duas entradas manuais independentes de estoque continuam representando duas entradas legítimas; reconhecer o mesmo documento físico exige sua identificação de negócio.

## Atualização das telas

O servidor emite somente invalidações `{scope}` por um canal Broadcast privado `workspace:<uuid>`. Não transmite linhas, conteúdo de OS, notas ou clientes. Há policy somente de recepção, validada por identidade, sessão e vínculo atual à empresa. Clientes não recebem permissão para publicar nesse canal.

O navegador agrupa eventos e reconsulta as APIs autorizadas da tela ativa. Reconstrói os cursores desde o início até a janela já carregada, preserva filtros e descarta respostas de contexto antigo. Há catch-up na inscrição, reconexão, foco, retorno à aba e à rede, além de conferência a cada 60 segundos enquanto a aba estiver visível. O intervalo mínimo entre refreshes é três segundos, com backoff e respeito ao Retry-After.

Rascunhos de modal mantêm sua revisão original. Alterações externas mostram aviso; campos sobrepostos exigem revisão. A troca de empresa/identidade encerra o canal, timers e respostas antigas. Remoção/bloqueio do vínculo é verificado nas consultas; a autorização em cache da conexão Realtime não substitui a autorização de cada operação. Uma falha de entrega do aviso não desfaz uma gravação válida.

## Validação e recuperação

- 248 testes JavaScript, incluindo os módulos reais, formulários, cursores, reconexão, conflitos e encadeamentos.
- 63 etapas de PostgreSQL 17 local: restauração estrutural, cinco migrações, permissões e rollback completo com equivalência estrutural.
- Quatro disputas SQL com duas sessões e espera por lock observada: convite, OS, recebimento e remarcação.
- 26 verificações HTTP em PostgREST local com COMMIT, incluindo duas contas disputando OS, início de análise, notas, recebimento parcial e agenda.

Os testes usam dados e contas sintéticos em loopback. O pacote em `outputs/concorrencia-sincronizacao-recuperacao.zip`, na workspace da tarefa, contém o estado anterior, código, estrutura, checksums e scripts de reversão. Não foi feita exportação de dados operacionais ou contas Auth.

As abas que estavam abertas antes desta publicação precisam ser atualizadas uma vez para carregar os novos scripts. A partir daí, mudanças de cards são recebidas automaticamente. Teste visual autenticado com a conta real do proprietário permanece distinto dos testes sintéticos e não deve ser declarado como realizado sem essa entrada real.
