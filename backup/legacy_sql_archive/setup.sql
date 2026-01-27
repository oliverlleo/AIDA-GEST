-- Enable pgcrypto for UUID and password hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Workspaces table (Each admin has one workspace)
CREATE TABLE IF NOT EXISTS public.workspaces (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    company_code TEXT NOT NULL UNIQUE,
    owner_id UUID REFERENCES auth.users(id) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Profiles table (To store user roles for Admins)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) PRIMARY KEY,
    workspace_id UUID REFERENCES public.workspaces(id),
    role TEXT DEFAULT 'admin',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Employees table (For staff members)
CREATE TABLE IF NOT EXISTS public.employees (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID REFERENCES public.workspaces(id) NOT NULL,
    name TEXT NOT NULL,
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    roles TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(workspace_id, username)
);

-- Enable RLS
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

-- Workspace Policies
DROP POLICY IF EXISTS "Admins can view their workspace" ON public.workspaces;
CREATE POLICY "Admins can view their workspace" ON public.workspaces
    FOR SELECT USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS "Admins can insert workspace" ON public.workspaces;
CREATE POLICY "Admins can insert workspace" ON public.workspaces
    FOR INSERT WITH CHECK (auth.uid() = owner_id);

-- Profile Policies
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile" ON public.profiles
    FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Employee Policies
-- Admins can view/manage employees in their workspace
DROP POLICY IF EXISTS "Admins can manage employees" ON public.employees;
CREATE POLICY "Admins can manage employees" ON public.employees
    USING (
        EXISTS (
            SELECT 1 FROM public.workspaces
            WHERE id = employees.workspace_id
            AND owner_id = auth.uid()
        )
    );

-- Allow public read access to employees table? No.
-- We will use a Secure Function for login.

-- RPC Function for Employee Login
CREATE OR REPLACE FUNCTION public.employee_login(
    p_company_code TEXT,
    p_username TEXT,
    p_password TEXT
) RETURNS TABLE (
    employee_id UUID,
    workspace_id UUID,
    name TEXT,
    roles TEXT[],
    token TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_workspace_id UUID;
    v_password_hash TEXT;
    v_employee_record RECORD;
BEGIN
    -- Find workspace by code
    SELECT id INTO v_workspace_id FROM public.workspaces WHERE company_code = p_company_code;

    IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION 'Invalid Company Code';
    END IF;

    -- Find employee
    SELECT * INTO v_employee_record FROM public.employees
    WHERE workspace_id = v_workspace_id AND username = p_username;

    IF v_employee_record.id IS NULL THEN
        RAISE EXCEPTION 'Invalid Username';
    END IF;

    -- Verify password
    -- Note: We are using crypt() to verify.
    IF v_employee_record.password_hash = crypt(p_password, v_employee_record.password_hash) THEN
        RETURN QUERY SELECT
            v_employee_record.id,
            v_employee_record.workspace_id,
            v_employee_record.name,
            v_employee_record.roles,
            'valid_session'::TEXT; -- In a real app, generate a JWT here or use a session table.
    ELSE
        RAISE EXCEPTION 'Invalid Password';
    END IF;
END;
$$;
