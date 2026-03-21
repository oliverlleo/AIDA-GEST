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
BEGIN
  -- Resolve workspace (assuming basic logic for demonstration, use actor context in production if preferred)
  v_workspace_id := (public.current_employee_from_token()).workspace_id;
  IF v_workspace_id IS NULL THEN
      -- Se a função for chamada com RLS normal, pega o workspace do tech
      SELECT workspace_id INTO v_workspace_id FROM employees WHERE id = p_technician_id;
  END IF;

  -- Load configuration
  SELECT settings INTO v_settings FROM technician_schedule_settings WHERE technician_id = p_technician_id;

  IF v_settings IS NULL THEN
      -- Fallback default se nao existir (0 a 6 para Domingo a Sábado)
      v_workdays := '[
          {"active": false, "start": "09:00", "end": "18:00"},
          {"active": true, "start": "09:00", "end": "18:00"},
          {"active": true, "start": "09:00", "end": "18:00"},
          {"active": true, "start": "09:00", "end": "18:00"},
          {"active": true, "start": "09:00", "end": "18:00"},
          {"active": true, "start": "09:00", "end": "18:00"},
          {"active": false, "start": "09:00", "end": "12:00"}
      ]'::jsonb;
      v_has_break := true;
      v_break_start := '12:00'::time;
      v_break_end := '13:00'::time;
      v_slot_duration := 30;
      v_max_concurrent := 1;
  ELSE
      v_workdays := v_settings->'workDays';
      v_has_break := (v_settings->>'hasBreak')::boolean;
      v_break_start := (v_settings->>'breakStart')::time;
      v_break_end := (v_settings->>'breakEnd')::time;
      v_slot_duration := COALESCE((v_settings->>'slotDuration')::integer, 30);
      v_max_concurrent := COALESCE((v_settings->>'maxConcurrent')::integer, 1);
  END IF;

  v_current_date := p_reference_date;
  v_end_date := p_reference_date + p_days - 1;

  WHILE v_current_date <= v_end_date LOOP
      -- Extrair o dia da semana (0=Domingo, 6=Sábado)
      v_dow := EXTRACT(DOW FROM v_current_date);
      v_day_config := v_workdays->v_dow;

      v_is_active := (v_day_config->>'active')::boolean;
      v_slots := ARRAY[]::jsonb[];

      IF v_is_active THEN
          v_start_time := (v_day_config->>'start')::time;
          v_end_time := (v_day_config->>'end')::time;

          -- Combina Data + Hora e converte explicitamente no fuso local para TIMESTAMP WITH TIME ZONE
          v_day_start_ts := (v_current_date + v_start_time) AT TIME ZONE 'America/Sao_Paulo';
          v_day_end_ts := (v_current_date + v_end_time) AT TIME ZONE 'America/Sao_Paulo';

          IF v_has_break THEN
              v_break_start_ts := (v_current_date + v_break_start) AT TIME ZONE 'America/Sao_Paulo';
              v_break_end_ts := (v_current_date + v_break_end) AT TIME ZONE 'America/Sao_Paulo';
          ELSE
              v_break_start_ts := v_day_start_ts - interval '1 second'; -- Passado para nao triggar break
              v_break_end_ts := v_day_start_ts - interval '1 second';
          END IF;

          -- Gerar os slots iterativamente somando o intervalo
          v_start_ts := v_day_start_ts;

          WHILE v_start_ts < v_day_end_ts LOOP
              v_slot_end_ts := v_start_ts + (v_slot_duration || ' minutes')::interval;

              -- Se esse slot extrapola o expediente, para
              IF v_slot_end_ts > v_day_end_ts THEN
                  EXIT;
              END IF;

              -- Ignora se estiver completamente dentro do intervalo de almoço
              IF NOT (v_start_ts >= v_break_start_ts AND v_slot_end_ts <= v_break_end_ts) THEN

                  -- Checar Bloqueios no Slot (Time Range ou Full Day)
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
                      -- Contar tickets agendados para aquele exato slot (start matching ou overlap)
                      -- Simplificação: tickets cuja data de inicio cai no slot.
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

                  -- Montar objeto do Slot (retornando ISO 8601 em UTC para o front interpretar)
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

      -- Adiciona o Dia
      v_days := array_append(v_days, jsonb_build_object(
          'date', v_current_date,
          'capacity', jsonb_build_object('total', array_length(v_slots, 1), 'booked', 0), -- Placeholder for summary map
          'slots', v_slots
      ));

      v_current_date := v_current_date + interval '1 day';
  END LOOP;

  RETURN jsonb_build_object('days', v_days);
END;
$function$
