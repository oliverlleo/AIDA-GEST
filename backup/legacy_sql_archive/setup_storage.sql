
-- Create Bucket 'ticket_photos'
INSERT INTO storage.buckets (id, name, public)
VALUES ('ticket_photos', 'ticket_photos', true)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS
-- ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Policy: Allow Upload (Insert) based on Workspace ID in Path
-- Path format: {workspace_id}/{ticket_id}/{filename}
DROP POLICY IF EXISTS "Allow Upload by Workspace" ON storage.objects;
CREATE POLICY "Allow Upload by Workspace" ON storage.objects
FOR INSERT TO anon, authenticated
WITH CHECK (
    bucket_id = 'ticket_photos' AND
    (storage.foldername(name))[1]::text = current_setting('request.headers', true)::json->>'x-workspace-id'
);

-- Policy: Allow Update/Delete based on Workspace ID
DROP POLICY IF EXISTS "Allow Modify by Workspace" ON storage.objects;
CREATE POLICY "Allow Modify by Workspace" ON storage.objects
FOR DELETE TO anon, authenticated
USING (
    bucket_id = 'ticket_photos' AND
    (storage.foldername(name))[1]::text = current_setting('request.headers', true)::json->>'x-workspace-id'
);

-- Policy: Public Read
DROP POLICY IF EXISTS "Allow Read by Workspace" ON storage.objects;
CREATE POLICY "Allow Read by Workspace" ON storage.objects
FOR SELECT TO anon, authenticated
USING (
    bucket_id = 'ticket_photos' AND
    (storage.foldername(name))[1]::text = current_setting('request.headers', true)::json->>'x-workspace-id'
);
