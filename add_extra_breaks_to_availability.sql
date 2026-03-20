CREATE OR REPLACE FUNCTION public.get_schedule_availability(p_technician_id uuid, p_mode text, p_reference_date date, p_days integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_workspace_id uuid;
  v_settings jsonb;
  v_workdays jsonb;
  v_has_break boolean;
  v_break_start time;
  v_break_end time;
  v_extra_breaks jsonb;
  v_slot_duration integer;
  v_max_concurrent integer;
  v_current_date date;
  v_end_date date;
  v_dow integer;
  v_day_config jsonb;
  v_is_active boolean;
  v_start_time time;
  v_end_time time;
  v_slots jsonb[];
  v_days jsonb[] := ARRAY[]::jsonb[];
  v_slot_record record;
  v_start_ts timestamp with time zone;
  v_end_ts timestamp with time zone;
  v_day_start_ts timestamp with time zone;
  v_day_end_ts timestamp with time zone;
  v_break_start_ts timestamp with time zone;
  v_break_end_ts timestamp with time zone;
  v_slot_end_ts timestamp with time zone;
  v_appointments jsonb[];
  v_booked integer;
  v_status text;
  v_block_record record;

  -- Para os intervalos extras
  v_eb jsonb;
  v_eb_is_active boolean;
  v_eb_start_time time;
  v_eb_end_time time;
  v_eb_start_ts timestamp with time zone;
  v_eb_end_ts timestamp with time zone;
  v_eb_recurrence_type text;
  v_eb_recurrence_days jsonb;
  v_eb_matches_day boolean;
  v_slot_in_extra_break boolean;
BEGIN
  v_workspace_id := (public.current_employee_from_token()).workspace_id;
  IF v_workspace_id IS NULL THEN
      SELECT workspace_id INTO v_workspace_id FROM employees WHERE id = p_technician_id;
  END IF;

  SELECT settings INTO v_settings FROM technician_schedule_settings WHERE technician_id = p_technician_id;

  IF v_settings IS NULL THEN
      v_workdays := '[{"active": false, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": true, "start": "09:00", "end": "18:00"}, {"active": false, "start": "09:00", "end": "12:00"}]'::jsonb;
      v_has_break := true;
      v_break_start := '12:00'::time;
      v_break_end := '13:00'::time;
      v_extra_breaks := '[]'::jsonb;
      v_slot_duration := 30;
      v_max_concurrent := 1;
  ELSE
      v_workdays := v_settings->'workDays';
      v_has_break := (v_settings->>'hasBreak')::boolean;
      v_break_start := (v_settings->>'breakStart')::time;
      v_break_end := (v_settings->>'breakEnd')::time;
      v_extra_breaks := COALESCE(v_settings->'extraBreaks', '[]'::jsonb);
      v_slot_duration := COALESCE((v_settings->>'slotDuration')::integer, 30);
      v_max_concurrent := COALESCE((v_settings->>'maxConcurrent')::integer, 1);
  END IF;

  v_current_date := p_reference_date;
  v_end_date := p_reference_date + p_days - 1;

  WHILE v_current_date <= v_end_date LOOP
      v_dow := EXTRACT(DOW FROM v_current_date);
      v_day_config := v_workdays->v_dow;

      v_is_active := (v_day_config->>'active')::boolean;
      v_slots := ARRAY[]::jsonb[];

      IF v_is_active THEN
          v_start_time := (v_day_config->>'start')::time;
          v_end_time := (v_day_config->>'end')::time;

          v_day_start_ts := (v_current_date + v_start_time) AT TIME ZONE 'America/Sao_Paulo';
          v_day_end_ts := (v_current_date + v_end_time) AT TIME ZONE 'America/Sao_Paulo';

          IF v_has_break THEN
              v_break_start_ts := (v_current_date + v_break_start) AT TIME ZONE 'America/Sao_Paulo';
              v_break_end_ts := (v_current_date + v_break_end) AT TIME ZONE 'America/Sao_Paulo';
          ELSE
              v_break_start_ts := v_day_start_ts - interval '1 second';
              v_break_end_ts := v_day_start_ts - interval '1 second';
          END IF;

          v_start_ts := v_day_start_ts;

          WHILE v_start_ts < v_day_end_ts LOOP
              v_slot_end_ts := v_start_ts + (v_slot_duration || ' minutes')::interval;

              IF v_slot_end_ts > v_day_end_ts THEN
                  EXIT;
              END IF;

              v_slot_in_extra_break := false;

              IF jsonb_typeof(v_extra_breaks) = 'array' AND jsonb_array_length(v_extra_breaks) > 0 THEN
                  FOR v_eb IN SELECT * FROM jsonb_array_elements(v_extra_breaks) LOOP
                      v_eb_is_active := (v_eb->>'active')::boolean;
                      IF v_eb_is_active THEN
                          v_eb_start_time := (v_eb->>'start')::time;
                          v_eb_end_time := (v_eb->>'end')::time;
                          v_eb_recurrence_type := v_eb->>'recurrence_type';
                          v_eb_recurrence_days := v_eb->'recurrence_days';

                          v_eb_start_ts := (v_current_date + v_eb_start_time) AT TIME ZONE 'America/Sao_Paulo';
                          v_eb_end_ts := (v_current_date + v_eb_end_time) AT TIME ZONE 'America/Sao_Paulo';

                          v_eb_matches_day := false;

                          IF v_eb_recurrence_type = 'daily' THEN
                              v_eb_matches_day := true;
                          ELSIF v_eb_recurrence_type = 'weekdays' THEN
                              IF EXTRACT(ISODOW FROM v_current_date) BETWEEN 1 AND 5 THEN
                                  v_eb_matches_day := true;
                              END IF;
                          ELSIF v_eb_recurrence_type = 'specific_days' THEN
                              IF v_eb_recurrence_days IS NOT NULL AND v_eb_recurrence_days @> to_jsonb(v_dow) THEN
                                  v_eb_matches_day := true;
                              END IF;
                          END IF;

                          IF v_eb_matches_day THEN
                              IF (v_start_ts < v_eb_end_ts AND v_slot_end_ts > v_eb_start_ts) THEN
                                  v_slot_in_extra_break := true;
                                  EXIT;
                              END IF;
                          END IF;
                      END IF;
                  END LOOP;
              END IF;

              IF NOT (v_start_ts >= v_break_start_ts AND v_slot_end_ts <= v_break_end_ts) AND NOT v_slot_in_extra_break THEN

                  v_block_record := NULL;
                  SELECT id, block_type, reason INTO v_block_record
                  FROM technician_schedule_blocks
                  WHERE technician_id = p_technician_id
                  AND (
                      (block_type = 'full_day' AND DATE(start_at AT TIME ZONE 'America/Sao_Paulo') = v_current_date)
                      OR
                      (block_type = 'time_range' AND start_at <= v_start_ts AND end_at >= v_slot_end_ts)
                  )
                  LIMIT 1;

                  IF v_block_record IS NOT NULL THEN
                      v_status := 'bloqueado';
                      v_booked := 0;
                  ELSE
                      SELECT count(*) INTO v_booked
                      FROM ticket_appointments
                      WHERE technician_id = p_technician_id
                        AND scheduled_start = v_start_ts
                        AND status NOT IN ('completed', 'cancelled')
                        AND deleted_at IS NULL;

                      IF v_booked >= v_max_concurrent THEN
                          v_status := 'lotado';
                      ELSIF v_booked > 0 THEN
                          v_status := 'ocupado';
                      ELSE
                          v_status := 'livre';
                      END IF;
                  END IF;

                  v_slots := array_append(v_slots, jsonb_build_object(
                      'start', v_start_ts,
                      'end', v_slot_end_ts,
                      'status', v_status,
                      'booked', COALESCE(v_booked, 0),
                      'block_id', v_block_record.id,
                      'block_notes', v_block_record.reason
                  ));

              END IF;

              v_start_ts := v_slot_end_ts;
          END LOOP;

      END IF;

      v_days := array_append(v_days, jsonb_build_object(
          'date', v_current_date,
          'capacity', jsonb_build_object('total', array_length(v_slots, 1), 'booked', 0),
          'slots', v_slots
      ));

      v_current_date := v_current_date + interval '1 day';
  END LOOP;

  RETURN jsonb_build_object('days', v_days);
END;
$function$
