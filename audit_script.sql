SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE
    (schemaname = 'storage' AND tablename = 'objects')
    OR
    (tablename IN ('tickets', 'employees'))
ORDER BY tablename, policyname;

SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'ticket_photos';
