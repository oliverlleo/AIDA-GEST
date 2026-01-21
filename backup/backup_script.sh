#!/bin/bash

# Configurações do Projeto
PROJECT_REF="cpydazjwlmssbzzsurxu"

echo "=========================================="
echo "Iniciando Backup Total do Supabase (AIDA-GEST)"
echo "Projeto: $PROJECT_REF"
echo "=========================================="

# Verificar se Supabase CLI está instalada
if ! command -v supabase &> /dev/null
then
    echo "ERRO: Supabase CLI não encontrada."
    echo "Instale via 'brew install supabase/tap/supabase' ou siga as instruções em INSTRUCTIONS.md"
    exit 1
fi

echo ""
echo "[1/3] Exportando Roles..."
supabase db dump --role-only --project-ref "$PROJECT_REF" -f backup/backup_roles.sql
if [ $? -eq 0 ]; then echo "OK"; else echo "FALHA ao exportar roles"; exit 1; fi

echo ""
echo "[2/3] Exportando Schema (Estrutura)..."
# Nota: --schema public padrão. Se precisar de auth, usar --schema auth (mas cuidado com dados sensíveis)
supabase db dump --project-ref "$PROJECT_REF" -f backup/backup_schema.sql
if [ $? -eq 0 ]; then echo "OK"; else echo "FALHA ao exportar schema"; exit 1; fi

echo ""
echo "[3/3] Exportando Dados (Conteúdo)..."
supabase db dump --data-only --project-ref "$PROJECT_REF" -f backup/backup_data.sql
if [ $? -eq 0 ]; then echo "OK"; else echo "FALHA ao exportar dados"; exit 1; fi

echo ""
echo "=========================================="
echo "Backup concluído com sucesso!"
echo "Arquivos salvos em ./backup/"
echo "=========================================="
ls -lh backup/*.sql
