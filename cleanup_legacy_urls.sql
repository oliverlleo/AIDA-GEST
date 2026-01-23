-- Cleanup Legacy Public URLs in Tickets
-- Convert 'https://.../public/ticket_photos/PATH' to 'PATH'
-- Column is TEXT[] not JSONB in this schema (based on array usage in JS)

UPDATE public.tickets
SET photos_urls = ARRAY(
    SELECT
        CASE
            WHEN url LIKE '%/object/public/ticket_photos/%' THEN
                substring(url from '/object/public/ticket_photos/(.*)$')
            ELSE
                url
        END
    FROM unnest(photos_urls) as url
)
WHERE photos_urls IS NOT NULL AND cardinality(photos_urls) > 0;
