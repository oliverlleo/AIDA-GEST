
-- 1. Enums
CREATE TYPE public.os_status AS ENUM (
    'new',
    'analyzing',
    'approval',
    'buying_parts',
    'repairing',
    'testing',
    'ready',
    'finished',
    'canceled'
);

CREATE TYPE public.os_priority AS ENUM (
    'low',
    'normal',
    'high',
    'urgent'
);

-- 2. Checklist Templates (For saving checklist models)
CREATE TABLE IF NOT EXISTS public.checklist_templates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID REFERENCES public.workspaces(id) NOT NULL,
    name TEXT NOT NULL,
    items JSONB NOT NULL, -- Array of strings e.g. ["Tela", "Bateria"]
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Service Orders Table
CREATE TABLE IF NOT EXISTS public.service_orders (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID REFERENCES public.workspaces(id) NOT NULL,

    -- Customer Info
    customer_name TEXT NOT NULL,
    customer_phone TEXT,

    -- Device Info
    device_model TEXT NOT NULL,
    serial_number TEXT,
    description TEXT NOT NULL, -- Defeito relatado

    -- Control
    status public.os_status DEFAULT 'new',
    priority public.os_priority DEFAULT 'normal',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    deadline TIMESTAMP WITH TIME ZONE, -- Prazo

    -- Users
    created_by UUID REFERENCES auth.users(id), -- Quem abriu (null se foi via funcionario rpc, tratar na app)
    technician_id UUID REFERENCES public.employees(id), -- Tecnico responsavel

    -- Process Data
    checklist JSONB DEFAULT '{}', -- { "Tela": true, "Bateria": false }
    photos_url TEXT[] DEFAULT '{}',

    -- Technical Analysis
    technical_notes TEXT,
    required_parts TEXT,

    -- Approval
    budget_value DECIMAL(10,2),
    budget_sent BOOLEAN DEFAULT FALSE,
    rejection_reason TEXT,

    -- Repair
    repair_success BOOLEAN,
    failure_notes TEXT,

    -- Search Vector (Optional for advanced search, but we use ILIKE for simplicity first)
    search_text TEXT GENERATED ALWAYS AS (
        customer_name || ' ' ||
        COALESCE(device_model, '') || ' ' ||
        COALESCE(serial_number, '') || ' ' ||
        COALESCE(id::text, '')
    ) STORED
);

-- 4. Service Logs Table
CREATE TABLE IF NOT EXISTS public.service_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    service_order_id UUID REFERENCES public.service_orders(id) ON DELETE CASCADE NOT NULL,
    user_id UUID, -- Pode ser auth.users(id) ou employee ID (texto?) vamos armazenar o ID e resolver o nome no front ou via join
    user_name TEXT, -- Snapshot do nome para facilitar
    action TEXT NOT NULL,
    details TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. RLS Policies

-- Enable RLS
ALTER TABLE public.checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_logs ENABLE ROW LEVEL SECURITY;

-- Helper function to check if user is admin or employee of workspace
CREATE OR REPLACE FUNCTION public.is_member_of_workspace(p_workspace_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Check if Owner
    IF EXISTS (SELECT 1 FROM public.workspaces WHERE id = p_workspace_id AND owner_id = auth.uid()) THEN
        RETURN TRUE;
    END IF;
    -- Check if Employee (The RPC login uses a specific role or context, but for RLS direct access:)
    -- NOTE: Since employees log in via RPC and don't have a real 'auth.uid()' session in Supabase Auth sense (unless we upgraded them),
    -- we might need to rely on the fact that the APP sends the query.
    -- HOWEVER, for this architecture where 'employee_session' is local, we need 'public' access controlled by the application logic OR
    -- we move to a model where we trust the client key for these tables if we can't authenticate the employee in Postgres.

    -- CURRENT ARCHITECTURE LIMITATION: Employees are NOT Supabase Auth Users.
    -- They cannot satisfy 'auth.uid()'.
    -- We will create a policy that allows access if the workspace matches, assuming the API key is valid.
    -- To secure this properly without Supabase Auth for employees, we would need to pass a JWT signed by us, or use RPCs for everything.
    -- For this prototype/MVP, we will allow access based on workspace_id existing.

    RETURN TRUE;
END;
$$;

-- Checklist Templates Policies
CREATE POLICY "Workspace Members Select Templates" ON public.checklist_templates
    FOR SELECT USING (true); -- Simplification for prototype: If you have the link/key, you can read. In prod, filter by workspace_id if passed in query.

CREATE POLICY "Admins Insert Templates" ON public.checklist_templates
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM public.workspaces WHERE id = workspace_id AND owner_id = auth.uid())
    );

-- Service Orders Policies
-- Since we are doing a "Backend Search" in the frontend code using .from('service_orders'), we need Select access.
-- We will assume the frontend filters by 'workspace_id'.
CREATE POLICY "Enable read access for all users" ON public.service_orders
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for all users" ON public.service_orders
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for all users" ON public.service_orders
    FOR UPDATE USING (true);

-- Logs Policies
CREATE POLICY "Enable read access for logs" ON public.service_logs
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for logs" ON public.service_logs
    FOR INSERT WITH CHECK (true);

-- 6. Storage Bucket Setup
-- Note: This often requires the service role key or running in SQL Editor.
INSERT INTO storage.buckets (id, name, public)
VALUES ('os-images', 'os-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage Policies
-- Allow public uploads for now (simplification)
CREATE POLICY "Public Access" ON storage.objects
    FOR SELECT USING (bucket_id = 'os-images');

CREATE POLICY "Public Insert" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'os-images');
