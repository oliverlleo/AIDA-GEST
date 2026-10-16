BEGIN;
DROP FUNCTION public.set_note_check_status(uuid,integer,text,boolean,boolean);
NOTIFY pgrst,'reload schema';
COMMIT;
