
-- Create Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id),
    name TEXT NOT NULL,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Enable RLS
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Policies for Suppliers
CREATE POLICY "Enable all access for users in same workspace" ON public.suppliers
    FOR ALL USING (workspace_id = (current_setting('request.headers'::text, true)::json->>'x-workspace-id')::uuid);

-- Add Columns to Tickets
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS is_outsourced BOOLEAN DEFAULT false;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_company_id UUID REFERENCES public.suppliers(id);
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_deadline TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_return_count INTEGER DEFAULT 0;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS outsourced_at TIMESTAMP WITH TIME ZONE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_tickets_outsourced_company_id ON public.tickets(outsourced_company_id);
