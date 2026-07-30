# Operação e implantação do estoque

## Antes de aplicar

1. Faça backup do banco e mantenha a branch de backup do frontend.
2. Revise as migrations e confirme que as migrations de integridade, contexto de ator, garantia e agenda já foram aplicadas.
3. Não ative o módulo antes de cadastrar pelo menos uma localização para os itens controlados.
4. Aplique primeiro em um ambiente de teste. Esta implementação não executa alterações destrutivas em OS antigas.

## Ordem das migrations

Execute exatamente nesta ordem:

1. `inventory_module_foundation.sql`
2. `inventory_workflow_integration.sql`
3. `inventory_purchase_and_consumption.sql`
4. `inventory_operations.sql`
5. `inventory_catalog_extension.sql`
6. `inventory_warranty_integration.sql`
7. `inventory_ticket_summaries.sql`
8. `inventory_returns.sql`
9. `inventory_location_validation.sql`
10. `inventory_movement_snapshots.sql`
11. `inventory_manual_entry.sql`
12. `inventory_creation_catalog.sql`
13. `inventory_location_and_images.sql`
14. `inventory_location_scheme_management.sql`

Depois de aplicar, atualize o cache de esquema da API, se necessário, e execute o checklist deste documento antes de habilitar o módulo.

## Ordem de rollback

O rollback é destinado a uma reversão completa e deve ser feito com o módulo desativado e sem operações abertas. Execute na ordem inversa:

1. `rollback_inventory_location_scheme_management.sql`
2. `rollback_inventory_location_and_images.sql`
3. `rollback_inventory_creation_catalog.sql`
4. `rollback_inventory_manual_entry.sql`
5. `rollback_inventory_movement_snapshots.sql`
6. `rollback_inventory_location_validation.sql`
7. `rollback_inventory_returns.sql`
8. `rollback_inventory_ticket_summaries.sql`
9. `rollback_inventory_warranty_integration.sql`
10. `rollback_inventory_catalog_extension.sql`
11. `rollback_inventory_operations.sql`
12. `rollback_inventory_purchase_and_consumption.sql`
13. `rollback_inventory_workflow_integration.sql`
14. `rollback_inventory_module.sql`

O rollback não apaga tickets nem altera os campos legados de peças.

## Ativação

1. Entre como administrador.
2. Abra `Gerenciamento`.
3. Ative a personalização de módulos, caso ainda esteja desligada.
4. Mantenha `Controle de compra de peças` ativo.
5. Ative `Estoque`.
6. Salve.
7. Abra `Estoque` no grupo `Gestão`.

Se houver solicitações, reservas ou compras abertas, o banco recusará a desativação e exibirá um aviso. Conclua ou cancele essas operações antes de tentar novamente.

## Cadastro inicial

1. Crie um padrão de localização livre ou estruturado.
2. Cadastre as localizações reais.
3. Cadastre cada peça. Somente o nome é obrigatório.
4. Marque `Controlar saldo` para itens físicos; deixe desligado para itens apenas de catálogo.
5. Informe mínimos, ideal, localização principal, modelos compatíveis e fornecedores.
6. Use `Entrada ou ajuste` e selecione `Registrar entrada`.
7. Informe quantidade, custo unitário quando conhecido e o motivo `Estoque inicial`.

Não use ajuste para registrar compra. Recebimentos de compra possuem fluxo próprio e atualizam o custo médio.

## Principais RPCs

| RPC | Uso |
| --- | --- |
| `get_inventory_dashboard` | Totais resumidos da tela. |
| `get_inventory_items_page` | Busca e filtros paginados. |
| `get_inventory_catalog_page` | Catálogo priorizado pelo modelo de uma OS existente. |
| `get_inventory_creation_catalog_page` | Catálogo priorizado durante a abertura da OS. |
| `request_ticket_inventory_parts` | Solicitação e reserva na análise, reparo ou criação direta. |
| `approve_ticket_with_inventory` | Reserva após aprovação e definição da próxima etapa. |
| `complete_repair_with_inventory` | Consumo, liberação e conclusão do reparo. |
| `return_ticket_inventory` | Devolução vinculada à OS. |
| `create_inventory_purchase` | Compra estruturada para faltas reais. |
| `receive_inventory_purchase` | Recebimento parcial ou total e custo médio. |
| `transfer_inventory` | Transferência transacional entre locais. |
| `adjust_inventory_stock` | Correção administrativa do saldo físico. |
| `register_inventory_entry` | Entrada manual auditada. |

## Checklist funcional

- Estoque desligado mantém criação, análise, compra e reparo legados.
- Estoque não pode ser ativado com controle de peças desligado.
- Admin vê o menu uma única vez; atendente vê o menu; técnico e testador não veem.
- Técnico pesquisa catálogo somente nas próprias OS e não recebe custos.
- Reserva total encaminha corretamente para agenda/reparo.
- Reserva parcial mantém o reservado e envia somente a falta para compra.
- Duas reservas simultâneas não conseguem usar a mesma última unidade.
- Orçamento negado, exclusão e finalização liberam reservas abertas.
- Peça descoberta no reparo pausa o cronômetro quando há falta.
- Recebimento parcial mantém o restante pendente.
- Recebimento atualiza físico, custo médio e última compra.
- Distribuição após recebimento exige confirmação.
- Conclusão consome somente o informado e libera o restante.
- Devolução cria novo movimento, sem editar o anterior.
- Alternativa nunca é aplicada automaticamente.
- Movimentação não pode ser alterada ou excluída pela API.
- Outro workspace não consegue consultar ou relacionar dados.
- Cards mostram apenas resumo e detalhes abrem sob demanda.

## Dados antigos

OS antigas continuam usando `parts_needed`, `parts_status` e `supplier_purchases`. Não há migração automática.

Uma migração futura deve ser opcional e assistida:

1. identificar textos recorrentes;
2. mapear manualmente cada texto para um item do catálogo;
3. criar `ticket_part_items` apenas após confirmação;
4. nunca inventar consumo ou custo histórico;
5. manter backup e relatório de tudo que foi convertido;
6. permitir rollback sem remover os textos originais.
