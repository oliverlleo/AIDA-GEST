
SELECT
    tablename,
    policyname,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename IN ('employees', 'outsourced_companies')
ORDER BY tablename;
