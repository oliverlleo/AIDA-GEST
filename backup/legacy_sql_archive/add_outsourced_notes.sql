
-- Adicionar coluna para histórico de notas de terceirizados
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_notes JSONB DEFAULT '[]'::JSONB;
