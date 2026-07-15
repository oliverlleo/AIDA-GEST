-- Permite iniciar um chamado já autorizado depois da análise, sem liberar combinações inválidas.
-- Reaproveita as etapas existentes: Compra Peca e Andamento Reparo.

BEGIN;

DO $migration$
DECLARE
    v_definition text;
BEGIN
    v_definition := pg_get_functiondef('public.validate_ticket_requirements()'::regprocedure);

    IF position($needle$IF (req_fields->>'analysis_deadline')::boolean IS TRUE THEN$needle$ IN v_definition) = 0
       OR position($needle$v_new_missing := (NEW.analysis_deadline IS NULL);$needle$ IN v_definition) = 0 THEN
        RAISE EXCEPTION 'Definição inesperada de validate_ticket_requirements; migração interrompida.';
    END IF;

    v_definition := replace(
        v_definition,
        $old$IF (req_fields->>'analysis_deadline')::boolean IS TRUE THEN$old$,
        $new$IF (req_fields->>'analysis_deadline')::boolean IS TRUE
           AND NOT (
               TG_OP = 'INSERT'
               AND NEW.budget_status = 'Aprovado'
               AND NEW.status IN ('Andamento Reparo', 'Compra Peca')
           ) THEN$new$
    );
    v_definition := replace(
        v_definition,
        $old$v_new_missing := (NEW.analysis_deadline IS NULL);$old$,
        $new$v_new_missing := (NEW.analysis_deadline IS NULL)
            AND NOT (
                TG_OP = 'INSERT'
                AND NEW.budget_status = 'Aprovado'
                AND NEW.status IN ('Andamento Reparo', 'Compra Peca')
            );$new$
    );

    EXECUTE v_definition;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.validate_ticket_approved_entry()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN
    -- Só os dois caminhos explícitos podem pular a análise na criação.
    IF TG_OP = 'INSERT' AND NEW.status IN ('Andamento Reparo', 'Compra Peca') THEN
        IF NEW.budget_status IS DISTINCT FROM 'Aprovado' THEN
            RAISE EXCEPTION 'Entrada direta em reparo ou compra exige orçamento aprovado.';
        END IF;

        IF NEW.status = 'Compra Peca'
           AND NULLIF(btrim(COALESCE(NEW.parts_needed, '')), '') IS NULL THEN
            RAISE EXCEPTION 'Informe as peças necessárias antes de enviar o chamado para compra.';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS validate_ticket_approved_entry ON public.tickets;
CREATE TRIGGER validate_ticket_approved_entry
BEFORE INSERT ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION public.validate_ticket_approved_entry();

COMMIT;
