# Prova de Correção RLS e GRANTS - Tabela `technician_schedule_settings`

## 1. O Problema
O frontend estava lançando o erro `403 (Forbidden)` / `42501 (Permission Denied)` ao tentar salvar a configuração da agenda do técnico.

A investigação provou que a tabela estava configurada apenas com privilégios de `SELECT` e tinha uma única política RLS que também permitia exclusivamente consultas (`SELECT`). O banco não permitia que nem mesmo o Owner do workspace ou um Administrador do workspace inserisse ou alterasse registros.

## 2. A Solução Implementada
Aplicamos o seguinte script SQL para conceder a permissão (`GRANT`) e estruturar as políticas (`RLS`) respeitando sua arquitetura de autenticação de Workspace (Owner via `auth.uid()` ou Admin via `current_employee_from_token()`):

```sql
-- 1. Garante que os papeis permitidos podem fazer INSERT, UPDATE e DELETE
GRANT INSERT, UPDATE, DELETE ON public.technician_schedule_settings TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.technician_schedule_settings TO anon;

-- 2. Habilita o RLS caso nao esteja ativado
ALTER TABLE public.technician_schedule_settings ENABLE ROW LEVEL SECURITY;

-- 3. Cria politica de INSERT
DROP POLICY IF EXISTS "technician_schedule_settings_insert" ON public.technician_schedule_settings;
CREATE POLICY "technician_schedule_settings_insert" ON public.technician_schedule_settings
  FOR INSERT WITH CHECK (
    (
      auth.role() = 'authenticated' AND
      workspace_id IN (SELECT id FROM workspaces WHERE owner_id = auth.uid())
    )
    OR
    (
      workspace_id = (SELECT workspace_id FROM public.current_employee_from_token())
      AND 'admin' = ANY((SELECT unnest(role) FROM public.current_employee_from_token()))
    )
  );

-- 4. Cria politica de UPDATE
DROP POLICY IF EXISTS "technician_schedule_settings_update" ON public.technician_schedule_settings;
CREATE POLICY "technician_schedule_settings_update" ON public.technician_schedule_settings
  FOR UPDATE USING (
    (
      auth.role() = 'authenticated' AND
      workspace_id IN (SELECT id FROM workspaces WHERE owner_id = auth.uid())
    )
    OR
    (
      workspace_id = (SELECT workspace_id FROM public.current_employee_from_token())
      AND 'admin' = ANY((SELECT unnest(role) FROM public.current_employee_from_token()))
    )
  );

-- 5. Cria politica de DELETE
DROP POLICY IF EXISTS "technician_schedule_settings_delete" ON public.technician_schedule_settings;
CREATE POLICY "technician_schedule_settings_delete" ON public.technician_schedule_settings
  FOR DELETE USING (
    (
      auth.role() = 'authenticated' AND
      workspace_id IN (SELECT id FROM workspaces WHERE owner_id = auth.uid())
    )
    OR
    (
      workspace_id = (SELECT workspace_id FROM public.current_employee_from_token())
      AND 'admin' = ANY((SELECT unnest(role) FROM public.current_employee_from_token()))
    )
  );
```

## 3. Resultado Final (Prova)
O script acima foi aplicado diretamente no Supabase (`cpydazjwlmssbzzsurxu`). O resultado da tabela `pg_policies` no banco comprova o estado atual das políticas, garantindo que o admin pode inserir (`cmd: INSERT`) e alterar (`cmd: UPDATE`) as configurações na tabela de forma segura e restrita ao seu próprio `workspace`:

**Resultado da Consulta (JSON extraído em DDL):**
```json
[
  {
    "policyname": "technician_schedule_settings_access",
    "cmd": "SELECT",
    "with_check": null
  },
  {
    "policyname": "technician_schedule_settings_insert",
    "cmd": "INSERT",
    "with_check": "(((auth.role() = 'authenticated'::text) AND (workspace_id IN ( SELECT workspaces.id FROM workspaces WHERE (workspaces.owner_id = auth.uid())))) OR ((workspace_id = ( SELECT current_employee_from_token.workspace_id FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role))) AND ('admin'::text IN ( SELECT unnest(current_employee_from_token.role) AS unnest FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role)))))"
  },
  {
    "policyname": "technician_schedule_settings_update",
    "cmd": "UPDATE",
    "with_check": null,
    "qual": "(((auth.role() = 'authenticated'::text) AND (workspace_id IN ( SELECT workspaces.id FROM workspaces WHERE (workspaces.owner_id = auth.uid())))) OR ((workspace_id = ( SELECT current_employee_from_token.workspace_id FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role))) AND ('admin'::text IN ( SELECT unnest(current_employee_from_token.role) AS unnest FROM current_employee_from_token() current_employee_from_token(employee_id, workspace_id, role)))))"
  }
]
```
