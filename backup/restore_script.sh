#!/bin/bash

# Configurações
PROJECT_REF="cpydazjwlmssbzzsurxu"
DB_HOST="db.$PROJECT_REF.supabase.co"
DB_USER="postgres"

echo "=========================================="
echo "⚠️  ATENÇÃO: SCRIPT DE RESTAURAÇÃO (ROLLBACK) ⚠️"
echo "Isso irá sobrescrever o banco de dados do projeto: $PROJECT_REF"
echo "=========================================="
echo ""
echo "Para continuar, você precisará da SENHA do banco de dados."
echo ""
read -p "Tem certeza que deseja prosseguir? (digite 'sim' para confirmar): " CONFIRM

if [ "$CONFIRM" != "sim" ]; then
    echo "Operação cancelada."
    exit 0
fi

echo ""
read -s -p "Digite a senha do banco de dados (postgres): " DB_PASSWORD
echo ""

# Exportar senha para evitar prompt repetitivo (psql usa PGPASSWORD)
export PGPASSWORD=$DB_PASSWORD

# URL de Conexão
DB_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/postgres"

echo ""
echo "[1/4] Restaurando Roles..."
psql "$DB_URL" -f backup/backup_roles.sql
if [ $? -ne 0 ]; then echo "❌ Erro ao restaurar Roles"; exit 1; fi

echo ""
echo "[2/4] Restaurando Schema (Estrutura)..."
# Opcional: Adicionar comandos para dropar schema public antes se necessário
# psql "$DB_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
psql "$DB_URL" -f backup/backup_schema.sql
if [ $? -ne 0 ]; then echo "❌ Erro ao restaurar Schema"; exit 1; fi

echo ""
echo "[3/4] Restaurando Dados..."
psql "$DB_URL" -f backup/backup_data.sql
if [ $? -ne 0 ]; then echo "❌ Erro ao restaurar Dados"; exit 1; fi

echo ""
echo "[4/4] Verificação Pós-Restore..."
# Contagem simples para validar
TABLE_COUNT=$(psql "$DB_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
echo "Tabelas no schema public: $TABLE_COUNT"

echo ""
echo "✅ Restauração Concluída!"
unset PGPASSWORD
