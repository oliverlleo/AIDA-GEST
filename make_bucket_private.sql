-- Make ticket_photos bucket private
UPDATE storage.buckets
SET public = false
WHERE id = 'ticket_photos';
