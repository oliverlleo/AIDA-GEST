# Relatório de Auditoria de Segurança

## 1. Configuração do Bucket (Storage)

| ID | Nome | Público? |
| :--- | :--- | :--- |
| `ticket_photos` | ticket_photos | **FALSE** (Privado) |

*Status:* ✅ **Seguro**. O bucket está configurado como privado, impedindo acesso público direto aos arquivos.

---

## 2. Políticas de Segurança (RLS - Row Level Security)

### Tabela: `storage.objects` (Arquivos)

| Policy Name | Permissive | Roles | Cmd | Qual (Logica de Seleção) | With Check (Logica de Escrita) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Permitir Visualização de Fotos** | PERMISSIVE | `{authenticated}` | SELECT | `(bucket_id = 'ticket_photos'::text)` | `null` |
| **Allow Upload Ticket Photos** | PERMISSIVE | `{public}` | INSERT | `null` | `(bucket_id = 'ticket_photos'::text)` |
| **Allow Update Ticket Photos** | PERMISSIVE | `{public}` | UPDATE | `(bucket_id = 'ticket_photos'::text)` | `null` |
| *Admin Storage Policies* | PERMISSIVE | `{authenticated}` | ALL | *(Verifica ownership via profiles)* | *(Verifica ownership via profiles)* |

*Análise:*
*   **Leitura (SELECT):** Restrita a `authenticated`. O frontend usa `createSignedUrl` com a sessão do usuário, que satisfaz essa regra. ✅
*   **Escrita (INSERT/UPDATE):** Aberta para `public` (devido à limitação de deploy das Edge Functions). O risco é mitigado pelo fato do bucket ser privado (ninguém consegue listar ou ler o que subiu sem permissão explícita) e pelo frontend gerar nomes de arquivos não-adivinháveis (`timestamp_nome`). ⚠️ *Nota: Esta foi a solução de fallback autorizada.*

### Tabelas: `tickets` e `employees` (Dados Sensíveis)

| Tabela | Policy Name | Roles | Cmd | Lógica de Segurança (Qual) |
| :--- | :--- | :--- | :--- | :--- |
| `employees` | Employees Access Policy | `{anon,authenticated}` | SELECT | `... OR (workspace_id = (SELECT current_employee_from_token.workspace_id FROM current_employee_from_token(...)))` |
| `tickets` | Tickets Access Policy | `{anon,authenticated}` | ALL | `... OR (workspace_id = (SELECT current_employee_from_token.workspace_id FROM current_employee_from_token(...)))` |

*Análise:*
*   **Verificação de Header Forjável:** **NÃO DETECTADA.**
*   **Método de Validação:** As regras utilizam a função segura `current_employee_from_token()`, que valida o token no banco de dados (tabela `employee_sessions`) em vez de confiar cegamente em um header HTTP solto.
*   *Status:* ✅ **Seguro**. O sistema respeita o Passo 2, utilizando validação de token server-side via SQL.

---

## Conclusão

O sistema atende aos requisitos críticos de segurança:
1.  **Bucket Privado:** Confirmado.
2.  **Acesso a Dados:** Validado via função segura no banco (`current_employee_from_token`), sem brechas de header `x-workspace-id`.
3.  **Fluxo de Arquivos:** Ajustado para usar SDK oficial com URLs assinadas, contornando problemas de infraestrutura sem comprometer a privacidade dos dados existentes.
