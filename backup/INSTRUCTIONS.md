# Backup Completo e Plano de Rollback - AIDA-GEST

Este documento fornece instruções passo a passo para realizar um backup completo do banco de dados Supabase e, se necessário, restaurá-lo (rollback).

**Data:** 11/02/2025
**Projeto:** AIDA-GEST (Supabase)
**Ambiente:** Produção (Assumido)

---

## 1. Pré-requisitos

Para executar o backup completo (Schema + Dados + Roles), você precisa da **Supabase CLI** instalada e logada na sua conta.

### Instalação (se necessário)
```bash
# MacOS/Linux (Homebrew)
brew install supabase/tap/supabase

# Windows (Scoop)
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
```

### Login e Link
```bash
# 1. Login na CLI (vai abrir o navegador)
supabase login

# 2. Linkar ao projeto remoto
# Substitua <project-ref> pelo ID do seu projeto (cpydazjwlmssbzzsurxu)
# Você precisará da senha do banco de dados.
supabase link --project-ref cpydazjwlmssbzzsurxu
```

---

## 2. Executando o Backup (Dump)

Execute estes comandos no terminal, na raiz deste projeto.

### 2.1. Backup do Schema (Estrutura)
Salva tabelas, views, funções (RPCs), triggers e políticas (RLS).
```bash
supabase db dump --db-url "postgresql://postgres:[SUA_SENHA]@db.cpydazjwlmssbzzsurxu.supabase.co:5432/postgres" -f backup/backup_schema.sql
```
*Nota: Se você já fez `supabase link`, pode usar apenas `supabase db dump -f backup/backup_schema.sql`.*

### 2.2. Backup dos Dados (Conteúdo)
Salva o conteúdo das tabelas (INSERTs). **Crítico para não perder clientes/tickets.**
```bash
supabase db dump --data-only --db-url "postgresql://postgres:[SUA_SENHA]@db.cpydazjwlmssbzzsurxu.supabase.co:5432/postgres" -f backup/backup_data.sql
```

### 2.3. Backup de Roles (Permissões Globais)
Salva usuários e permissões de nível de banco (caso existam customizações fora do padrão).
```bash
supabase db dump --role-only --db-url "postgresql://postgres:[SUA_SENHA]@db.cpydazjwlmssbzzsurxu.supabase.co:5432/postgres" -f backup/backup_roles.sql
```

---

## 3. Plano de Restauração (Rollback)

**⚠️ PERIGO:** A restauração pode sobrescrever dados atuais. Execute apenas se o sistema estiver quebrado e você precisar voltar ao estado anterior.

### Ordem de Execução
1.  **Roles (Permissões)**
2.  **Schema (Estrutura)**
3.  **Data (Dados)**

### Comandos de Restore

```bash
# 1. Restaurar Roles (Geralmente não é necessário se o projeto é o mesmo, mas por segurança)
psql -h db.cpydazjwlmssbzzsurxu.supabase.co -U postgres -f backup/backup_roles.sql

# 2. Restaurar Schema (Recria tabelas/funções)
# Aviso: Isso pode falhar se as tabelas já existirem. O ideal é limpar o schema public antes em um caso de desastre total.
psql -h db.cpydazjwlmssbzzsurxu.supabase.co -U postgres -f backup/backup_schema.sql

# 3. Restaurar Dados
psql -h db.cpydazjwlmssbzzsurxu.supabase.co -U postgres -f backup/backup_data.sql
```

---

## 4. Validação do Backup

Após gerar os arquivos `.sql` na pasta `backup/`, verifique:

1.  **Tamanho dos arquivos:** `backup_data.sql` deve ter um tamanho considerável (KB ou MB) dependendo do volume de tickets. `backup_schema.sql` deve conter definições de `CREATE TABLE`, `CREATE FUNCTION`, etc.
2.  **Conteúdo Crítico:** Abra `backup_schema.sql` e procure por:
    *   `CREATE TABLE public.tickets`
    *   `CREATE FUNCTION public.employee_login`
    *   `CREATE POLICY` (RLS)
3.  **Dados:** Abra `backup_data.sql` e procure por `COPY public.tickets` ou `INSERT INTO public.tickets`.

Se esses elementos estiverem presentes, o backup está tecnicamente íntegro.

---

## 5. Arquivos Gerados (Esperado)

Ao final do processo, você deve ter nesta pasta:
*   `backup_schema.sql`
*   `backup_data.sql`
*   `backup_roles.sql`
*   `INSTRUCTIONS.md` (este arquivo)
*   `legacy_sql_archive/` (pasta com scripts antigos removidos da raiz)
