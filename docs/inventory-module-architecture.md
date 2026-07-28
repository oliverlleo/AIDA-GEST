# Módulo de estoque

## Objetivo e compatibilidade

O estoque evolui o controle de peças já existente. Ele não cria etapas novas no Kanban e não remove os campos legados `parts_needed`, `parts_status` e `supplier_purchases`.

O comportamento depende de duas configurações:

- `workflow.parts_control`: habilita o fluxo de peças e compras.
- `modules.inventory`: habilita catálogo, saldo, reserva, consumo e compras estruturadas.

`modules.inventory` é `false` por padrão. Se `parts_control` estiver desligado, o estoque também fica indisponível. Com o estoque desligado, todos os fluxos continuam usando o comportamento legado.

## Modelo de dados

| Tabela | Responsabilidade |
| --- | --- |
| `inventory_items` | Cadastro da peça, unidade, mínimos, ideal, foto, códigos e arquivamento. |
| `inventory_item_costs` | Custo médio e custo da última compra, separado do catálogo consultado por técnicos. |
| `inventory_location_schemes` | Definição visual dos endereços livres ou estruturados. |
| `inventory_locations` | Locais físicos únicos dentro do workspace. |
| `inventory_balances` | Saldo físico, reservado e disponível por peça e localização. |
| `inventory_item_models` | Compatibilidade entre peças e modelos de aparelhos. |
| `inventory_item_suppliers` | Relação com os fornecedores já existentes. |
| `inventory_item_relations` | Equivalências bidirecionais e substituições direcionais. |
| `ticket_part_items` | Peças solicitadas por OS e pela etapa que originou a solicitação. |
| `inventory_reservations` | Reserva, consumo, liberação e devolução por OS. |
| `inventory_purchases` | Cabeçalho e situação da compra estruturada. |
| `inventory_purchase_items` | Itens, quantidades, custo e snapshot do fornecedor. |
| `inventory_purchase_allocations` | Distribuição recebida para as OS pendentes. |
| `inventory_movements` | Livro imutável de todas as alterações de saldo e reserva. |

O saldo disponível é uma coluna gerada:

```text
disponível = físico - reservado
```

Constraints impedem valores negativos e reserva maior que o físico.

## Fluxos

### Análise e aprovação

O técnico seleciona peças compatíveis ou pesquisa o catálogo completo. A análise registra a necessidade, sem consumir. Após a aprovação, a função transacional bloqueia os saldos, reserva o disponível e:

- libera o reparo quando tudo está reservado;
- mantém a reserva parcial e envia somente a falta para `Compra Peca`;
- respeita a agenda de reparo quando a etapa está habilitada.

### OS direta para reparo

O formulário permite escolher peças antes da criação. A OS é criada com ID previamente definido e, em seguida, a função de estoque registra e reserva as peças. Estoque suficiente segue para reparo; falta total ou parcial segue para compra.

### Peça descoberta no reparo

“Adicionar peça” usa a mesma função de solicitação. Se faltar saldo, o reparo é pausado, o tempo acumulado é preservado e a OS vai para compra. Ao receber e reservar tudo, o reparo retoma do tempo anterior.

### Conclusão, liberação e devolução

Na conclusão, o técnico confirma a quantidade realmente usada. O consumo reduz o físico; o restante libera a reserva. Uma devolução posterior gera entrada vinculada à mesma reserva, movimentação e histórico, sem editar o movimento original.

### Compras

Uma compra contém fornecedor, snapshots, itens e alocações. O recebimento pode ser parcial. O custo médio é recalculado apenas nas entradas. A distribuição é confirmada pelo usuário e prioriza:

1. solicitação de prioridade;
2. solicitação mais antiga;
3. identificador estável em caso de empate.

## Segurança

- Todas as tabelas usam RLS.
- O acesso direto às tabelas é revogado de `public`, `anon` e `authenticated`.
- Escritas críticas são feitas somente por RPC transacional.
- RPCs públicas não recebem `workspace_id`, usuário responsável ou nome do ator do frontend.
- O contexto vem de `get_current_actor_context()`.
- Funções `SECURITY DEFINER` usam `search_path = ''`.
- Saldos e reservas são bloqueados com `FOR UPDATE`.
- Movimentações não podem ser editadas ou excluídas.
- Chaves compostas impedem relações entre workspaces.
- A desativação é bloqueada enquanto houver reservas, solicitações ou compras abertas.

## Matriz de permissões

| Ação | Admin | Atendente | Técnico | Testador |
| --- | :---: | :---: | :---: | :---: |
| Ativar/desativar estoque | Sim | Não | Não | Não |
| Ver tela de estoque e custos | Sim | Sim | Não | Não |
| Cadastrar, editar e arquivar item | Sim | Não | Não | Não |
| Entrada e ajuste manual | Sim | Não | Não | Não |
| Transferir estoque | Sim | Não | Não | Não |
| Criar/receber/cancelar compra | Sim | Sim | Não | Não |
| Pesquisar catálogo na OS | Sim | Sim | Própria OS | Não |
| Solicitar/reservar/consumir/devolver | Sim | Conforme fluxo | Própria OS | Não |

## Desempenho

- Lista de itens e movimentações usam paginação por cursor.
- Busca e filtros rodam no banco.
- Os cards das OS recebem somente um resumo, em lotes de até 100 IDs já carregados.
- Detalhes, custos, reservas e movimentos são carregados somente ao abrir a tela ou modal correspondente.
- Nenhuma consulta nova carrega todas as OS ou todas as movimentações.

## Frontend

- `js/modules/inventory-query-service.js`: páginas, resumos e catálogo.
- `js/modules/inventory-catalog-service.js`: itens, locais, entradas e ajustes.
- `js/modules/inventory-actions.js`: solicitações e mensagens de roteamento.
- `js/modules/inventory-management-service.js`: compras, vínculos, transferências e devoluções.
- `js/main.js`: estado da tela, navegação e integração com os fluxos existentes.
