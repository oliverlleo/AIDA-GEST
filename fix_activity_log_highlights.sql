-- Destaca os dados importantes dos novos registros de agenda e identifica a OS.
-- Preserva toda a validação de acesso e capacidade já existente nas RPCs.

BEGIN;

DO $migration$
DECLARE
    v_def text;
BEGIN
    v_def := pg_get_functiondef(
        'public.create_ticket_appointment(uuid,uuid,text,timestamptz,timestamptz,text)'::regprocedure
    );

    IF position('SELECT t.device_model, t.client_name' IN v_def) = 0 THEN
        RAISE EXCEPTION 'Definição inesperada de create_ticket_appointment; migração interrompida.';
    END IF;

    v_def := replace(
        v_def,
        $old$SELECT t.device_model, t.client_name$old$,
        $new$SELECT t.os_number, t.device_model, t.client_name$new$
    );
    v_def := replace(
        v_def,
        $old$'Agendamento de %s do aparelho %s do cliente %s criado com o técnico %s para %s, das %s às %s.',
            v_type_label,
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_technician_name,
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            to_char(p_scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')$old$,
        $new$'Agendamento de %s da OS **%s** — aparelho **%s** do cliente **%s** — criado com o técnico **%s** para **%s**, das **%s** às **%s**.',
            v_type_label,
            COALESCE(v_ticket.os_number::text, 'não informada'),
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            v_technician_name,
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
            to_char(p_scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            to_char(p_scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')$new$
    );
    EXECUTE v_def;

    v_def := pg_get_functiondef(
        'public.reschedule_ticket_appointment(uuid,uuid,timestamptz,timestamptz,text)'::regprocedure
    );

    IF position('SELECT t.device_model, t.client_name, old_tech.name AS old_technician_name' IN v_def) = 0 THEN
        RAISE EXCEPTION 'Definição inesperada de reschedule_ticket_appointment; migração interrompida.';
    END IF;

    v_def := replace(
        v_def,
        $old$SELECT t.device_model, t.client_name, old_tech.name AS old_technician_name$old$,
        $new$SELECT t.os_number, t.device_model, t.client_name, old_tech.name AS old_technician_name$new$
    );
    v_def := replace(
        v_def,
        $old$'Agendamento de %s do aparelho %s do cliente %s',
        v_type_label,
        COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado')$old$,
        $new$'Agendamento de %s da OS **%s** — aparelho **%s** do cliente **%s**',
        v_type_label,
        COALESCE(v_ticket.os_number::text, 'não informada'),
        COALESCE(v_ticket.device_model, 'não informado'),
        COALESCE(v_ticket.client_name, 'não informado')$new$
    );
    v_def := replace(
        v_def,
        $old$' teve o técnico alterado de %s para %s'$old$,
        $new$' teve o técnico alterado de **%s** para **%s**'$new$
    );
    v_def := replace(
        v_def,
        $old$' manteve o técnico %s'$old$,
        $new$' manteve o técnico **%s**'$new$
    );
    v_def := replace(
        v_def,
        $old$'; data e horário alterados de %s para %s.'$old$,
        $new$'; data e horário alterados de **%s** para **%s**.'$new$
    );
    EXECUTE v_def;

    v_def := pg_get_functiondef(
        'public.cancel_ticket_appointment(uuid,text)'::regprocedure
    );

    IF position('SELECT t.device_model, t.client_name, e.name AS technician_name' IN v_def) = 0 THEN
        RAISE EXCEPTION 'Definição inesperada de cancel_ticket_appointment; migração interrompida.';
    END IF;

    v_def := replace(
        v_def,
        $old$SELECT t.device_model, t.client_name, e.name AS technician_name$old$,
        $new$SELECT t.os_number, t.device_model, t.client_name, e.name AS technician_name$new$
    );
    v_def := replace(
        v_def,
        $old$'Agendamento de %s do aparelho %s do cliente %s com o técnico %s em %s, das %s às %s, foi cancelado%s.',
            v_type_label,
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            COALESCE(v_ticket.technician_name, 'não informado'),
            to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
            to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            to_char(v_app.scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            CASE WHEN p_reason IS NOT NULL AND btrim(p_reason) <> '' THEN ': ' || p_reason ELSE '' END$old$,
        $new$'Agendamento de %s da OS **%s** — aparelho **%s** do cliente **%s** — com o técnico **%s** em **%s**, das **%s** às **%s**, foi cancelado%s.',
            v_type_label,
            COALESCE(v_ticket.os_number::text, 'não informada'),
            COALESCE(v_ticket.device_model, 'não informado'),
            COALESCE(v_ticket.client_name, 'não informado'),
            COALESCE(v_ticket.technician_name, 'não informado'),
            to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY'),
            to_char(v_app.scheduled_start AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            to_char(v_app.scheduled_end AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
            CASE WHEN p_reason IS NOT NULL AND btrim(p_reason) <> '' THEN ': ' || p_reason ELSE '' END$new$
    );
    EXECUTE v_def;
END;
$migration$;

COMMIT;
