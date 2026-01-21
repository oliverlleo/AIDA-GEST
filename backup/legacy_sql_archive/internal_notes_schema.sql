
-- ==============================================================================
-- INTERNAL NOTES SYSTEM (CHAT & GENERAL NOTES)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.internal_notes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,

    -- Context
    ticket_id UUID REFERENCES public.tickets(id) ON DELETE CASCADE, -- NULL = General Note

    -- Author
    author_id UUID NOT NULL,
    author_name TEXT NOT NULL,

    -- Content
    content TEXT NOT NULL,
    checklist_data JSONB DEFAULT '[]'::JSONB, -- Array of {item: string, ok: bool}
    mentions TEXT[] DEFAULT '{}', -- Array of User IDs or 'all'

    -- Status
    is_resolved BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,
    archived_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- RLS
ALTER TABLE public.internal_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Acesso Total Notas" ON public.internal_notes;
CREATE POLICY "Acesso Total Notas" ON public.internal_notes FOR ALL USING (true) WITH CHECK (true);

-- Permissions
GRANT ALL ON TABLE public.internal_notes TO anon, authenticated, service_role;

-- Force Schema Cache Reload
NOTIFY pgrst, 'reload schema';
