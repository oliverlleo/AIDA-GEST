# Backup Completo e Plano de Rollback - AIDA-GEST

Este documento fornece instruções rigorosas para realizar backup e restauração (rollback) do banco de dados Supabase.

**Data:** 11/02/2025
**Projeto:** AIDA-GEST (cpydazjwlmssbzzsurxu)
**Ambiente:** Produção

---

## 1. Pré-requisitos

Certifique-se de ter a **Supabase CLI** instalada e autenticada.

```bash
# Verificar instalação
supabase --version

# Login (se necessário)
supabase login

# Linkar ao projeto (necessário senha do DB)
supabase link --project-ref cpydazjwlmssbzzsurxu
```

---

## 2. Executando o Backup (Dump)

Utilize o script automatizado `backup_script.sh` ou execute os comandos abaixo manualmente.

### 2.1. Backup de Roles (Permissões Globais)
Essencial para preservar usuários de banco customizados e grants.
```bash
supabase db dump --role-only --project-ref cpydazjwlmssbzzsurxu -f backup/backup_roles.sql
```

### 2.2. Backup do Schema (Estrutura Completa)
Salva definições de tabelas, views, funções, triggers e políticas RLS.
```bash
supabase db dump --project-ref cpydazjwlmssbzzsurxu -f backup/backup_schema.sql
```

### 2.3. Backup dos Dados (Conteúdo)
Salva os dados das tabelas (INSERTs). **Crítico.**
```bash
supabase db dump --data-only --project-ref cpydazjwlmssbzzsurxu -f backup/backup_data.sql
```

### 2.4. Nota sobre o Schema `auth`
O Supabase gerencia o schema `auth` (tabela `users`, etc.). O comando `supabase db dump` foca nos schemas do usuário (`public`).
*   **Atenção:** Se você tiver triggers ou foreign keys apontando para `auth.users` no schema `public`, o `backup_schema.sql` deve conter essas referências.
*   **Dados de Auth:** O dump padrão **NÃO** exporta senhas ou dados sensíveis de `auth.users` por segurança. Se precisar de backup total de usuários para migração entre projetos, utilize a opção de exportar usuários pelo Dashboard ou scripts específicos de administração, mas para rollback no **mesmo** projeto, a estrutura do `public` é a prioridade.

---

## 3. Plano de Restauração (Rollback)

Use o script `restore_script.sh` para automatizar ou siga a ordem abaixo.

**⚠️ ALERTA DE PERIGO:** O restore apaga/sobrescreve o estado atual. Use somente em caso de falha crítica.

### Ordem Obrigatória
1.  **Roles:** Restaurar permissões primeiro.
2.  **Schema:** Recriar a estrutura (Tabelas/Funções).
3.  **Dados:** Re popular as tabelas.

### Comando Manual (via psql)
Você precisará da string de conexão (Connection String) do seu banco.

```bash
# Exemplo de Connection String
DB_URL="postgresql://postgres:[SENHA]@db.cpydazjwlmssbzzsurxu.supabase.co:5432/postgres"

# 1. Restaurar Roles
psql "$DB_URL" -f backup/backup_roles.sql

# 2. Restaurar Schema
# (Recomendado: Limpar o schema public antes se estiver corrompido)
psql "$DB_URL" -f backup/backup_schema.sql

# 3. Restaurar Dados
psql "$DB_URL" -f backup/backup_data.sql
```

---

## 4. Checklist Final: Backup OK

Antes de prosseguir com qualquer migração, verifique:

- [ ] Arquivo `backup/backup_roles.sql` existe e não está vazio.
- [ ] Arquivo `backup/backup_schema.sql` existe e contém `CREATE TABLE public.tickets`.
- [ ] Arquivo `backup/backup_data.sql` existe e contém dados (`COPY` ou `INSERT`).
- [ ] Você possui a senha do banco de dados (`postgres`) salva e acessível.
- [ ] O script `restore_script.sh` foi revisado e compreendido.

Se todos os itens estiverem marcados, o backup é considerado válido.
