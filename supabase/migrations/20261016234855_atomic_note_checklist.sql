-- Change a single checklist item under the note row lock; never replace a stale array.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
CREATE FUNCTION public.set_note_check_status(
 p_note_id uuid,p_item_index integer,p_item_text text,p_expected_ok boolean,p_new_ok boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE v_ctx record; v_note public.internal_notes%ROWTYPE; v_item jsonb; v_current boolean;
BEGIN
 SELECT * INTO v_ctx FROM public.get_current_actor_context();
 IF p_note_id IS NULL OR p_item_index IS NULL OR p_item_index<0
    OR p_item_text IS NULL OR p_expected_ok IS NULL OR p_new_ok IS NULL THEN
  RAISE EXCEPTION 'Item da nota invalido.' USING ERRCODE='22023';
 END IF;
 SELECT n.* INTO v_note FROM public.internal_notes n
  WHERE n.id=p_note_id AND n.workspace_id=v_ctx.workspace_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Nota indisponivel para este acesso.' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(v_note.checklist_data)<>'array' OR p_item_index>=jsonb_array_length(v_note.checklist_data) THEN
  RAISE EXCEPTION 'A lista da nota mudou. Atualize antes de marcar o item.' USING ERRCODE='PT409';
 END IF;
 v_item:=v_note.checklist_data->p_item_index;
 IF v_item->>'item' IS DISTINCT FROM p_item_text OR jsonb_typeof(v_item->'ok') IS DISTINCT FROM 'boolean' THEN
  RAISE EXCEPTION 'O item da nota mudou. Atualize antes de marcar.' USING ERRCODE='PT409';
 END IF;
 v_current:=(v_item->>'ok')::boolean;
 -- Repeating the same desired state has no additional effect.
 IF v_current=p_new_ok THEN RETURN to_jsonb(v_note); END IF;
 IF v_current IS DISTINCT FROM p_expected_ok THEN
  RAISE EXCEPTION 'O item foi alterado em outro acesso. Revise antes de marcar.' USING ERRCODE='PT409';
 END IF;
 UPDATE public.internal_notes SET checklist_data=jsonb_set(
  checklist_data,ARRAY[p_item_index::text,'ok'],to_jsonb(p_new_ok),false
 ) WHERE id=v_note.id AND workspace_id=v_ctx.workspace_id RETURNING * INTO v_note;
 IF NOT FOUND THEN RAISE EXCEPTION 'Nota indisponivel para alteracao.' USING ERRCODE='42501'; END IF;
 RETURN to_jsonb(v_note);
END $$;
ALTER FUNCTION public.set_note_check_status(uuid,integer,text,boolean,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.set_note_check_status(uuid,integer,text,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_note_check_status(uuid,integer,text,boolean,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
