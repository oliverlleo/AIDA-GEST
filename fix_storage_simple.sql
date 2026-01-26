
-- Tentar apenas atualizar o bucket para privado
UPDATE storage.buckets
SET public = false
WHERE id = 'ticket_photos';

-- Se o bucket não existir, criar como privado
INSERT INTO storage.buckets (id, name, public)
VALUES ('ticket_photos', 'ticket_photos', false)
ON CONFLICT (id) DO NOTHING;
