
ALTER TABLE checklist_templates
ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'entry';
