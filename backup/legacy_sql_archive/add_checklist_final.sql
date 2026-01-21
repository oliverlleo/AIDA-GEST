
ALTER TABLE tickets
ADD COLUMN IF NOT EXISTS checklist_final_data JSONB DEFAULT '[]'::jsonb;
