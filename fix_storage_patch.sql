DROP POLICY IF EXISTS "Strict Upload Access via Ticket" ON storage.objects;

CREATE POLICY "Strict Upload Access via Ticket"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (
  bucket_id = 'ticket_photos'
  AND EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id::text = (storage.foldername(name))[1]
  )
);
