# Revisão visual e responsiva do CentralOS

Branch: `codex/design-apple-responsive`
Base analisada: `5468b96fda8a2ce1959af8ea772b663ee768a103`
Data: 8 de setembro de 2026

## Implementação

As páginas `index.html` e `acompanhar.html` passam a compartilhar a paleta e a tipografia de `js/design-config.js` e os componentes visuais de `css/design-system.css`. A referência é a hierarquia e o uso moderado de materiais da [Apple](https://developer.apple.com/design/human-interface-guidelines/materials), mantendo a identidade laranja do CentralOS e as cores dos estados operacionais.

- Navegação lateral no desktop e faixa horizontal com nomes das seções em celulares e tablets. A faixa permite rolar até todas as opções autorizadas.
- Superfícies, botões, formulários, seletores, abas, tabelas, notificações, painéis laterais e modais compartilham os mesmos padrões de apresentação.
- A área principal usa a altura dinâmica disponível. Listas e tabelas mantêm rolagem dentro de suas regiões; a tela de configuração também permite rolagem vertical.
- Formulários de uma coluna não geram colunas implícitas pelos spans antigos. Busca do Kanban, ações dos chamados e cabeçalhos se reorganizam em telas pequenas.
- Modais com altura limitada permitem rolar seu conteúdo. O painel de agendamento ocupa a largura disponível no celular, e os fundos dos modais não interceptam cliques nos formulários.
- Controles de toque têm altura mínima de 44 px no celular. Campos usam 16 px para evitar o zoom automático de entrada no iOS. Há foco visível por teclado, respeito a movimento reduzido, ajustes de contraste/transparência e áreas seguras.
- As cores e a logo escolhidas pelo cliente para a página pública continuam sendo aplicadas pelos mesmos vínculos existentes.

## Validação

Os 134 testes existentes passaram antes e depois da alteração. A comparação das páginas com a base confirmou que os 2.690 conjuntos de atributos de comportamento/validação da página principal e os 42 da página pública permanecem iguais: eventos, condições, modelos de dados, permissões, tipos e restrições de campos.

O teste `tests/design-responsive.cjs` usa um servidor local isolado, substitui a inicialização somente na resposta de teste e usa dados sintéticos. Ele não autentica nem grava no serviço real. A aplicação distribuída não contém essa substituição.

A rodada de referência passou em **229 verificações de estados/telas**, sem transbordamento horizontal não rolável detectado e sem erros de JavaScript:

- Larguras de 320, 390, 768 e 1440 px; janela curta de 844 × 390 px.
- Seções disponíveis para o administrador, modais declarados no estado, notas, compartilhamento, fila da visão geral e painel de agendamento.
- Clientes e estoque com dados sintéticos; detalhes de chamado; abas de detalhes, notas e agendamentos; abas dos cadastros.
- Navegação real por clique; preenchimento e cancelamento; modal de cliente sobre o de chamado preservando o formulário; acesso de atendente, técnico e tester; login, foco por teclado e acompanhamento público.

Para repetir, com Node.js e Playwright disponíveis:

```sh
node --test tests/*.test.js
node tests/design-responsive.cjs
```

Se necessário, instale apenas a dependência de teste e seu navegador:

```sh
npm install --no-save --package-lock=false playwright
npx playwright install chromium
```

`AIDA_BROWSER_PATH` permite usar um executável Chromium local. `AIDA_DESIGN_RESULTS` muda a pasta de resultados, que por padrão é `test-results/design/`. O teste salva capturas e `report.json` com os resultados por estado.

## Limites e publicação

Os módulos de negócio, SQL, serviços, autenticação e configuração real de conexão não foram alterados. A validação visual em Chromium com dados sintéticos não substitui a homologação de gravações reais, integrações, uploads ou testes em aparelhos iOS/Safari e Android. A análise automatizada verifica limites horizontais e interações selecionadas; não certifica todos os estados possíveis nem acessibilidade completa.

A proposta fica isolada na branch para revisão antes de integração ou publicação. Nenhuma migração de banco é necessária. A reversão consiste em reverter o commit visual, incluindo os dois arquivos compartilhados e as referências nas páginas.
