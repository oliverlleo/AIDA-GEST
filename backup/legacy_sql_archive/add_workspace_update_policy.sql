
-- Allow admins to update their workspace (e.g. tracker_config, whatsapp_number)
DROP POLICY IF EXISTS "Admins can update own workspace" ON public.workspaces;
CREATE POLICY "Admins can update own workspace" ON public.workspaces
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);
