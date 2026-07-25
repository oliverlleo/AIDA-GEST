-- Warranty-return workflow.
-- Keeps warranty claims inside the existing ticket stages while preserving
-- the original OS, the technical decision and any paid follow-up OS.

begin;

alter table public.tickets
    add column if not exists warranty_claim boolean not null default false,
    add column if not exists warranty_origin_ticket_id uuid,
    add column if not exists warranty_source_claim_id uuid,
    add column if not exists warranty_converted_ticket_id uuid,
    add column if not exists warranty_status text,
    add column if not exists warranty_days integer,
    add column if not exists warranty_start_at timestamptz,
    add column if not exists warranty_expires_at timestamptz,
    add column if not exists warranty_technical_report text,
    add column if not exists warranty_needs_parts boolean,
    add column if not exists warranty_decided_at timestamptz,
    add column if not exists warranty_decided_by uuid,
    add column if not exists warranty_decided_by_name text;

alter table public.tickets
    drop constraint if exists tickets_warranty_status_check,
    add constraint tickets_warranty_status_check
        check (
            warranty_status is null
            or warranty_status in ('pending', 'covered', 'not_covered')
        ),
    drop constraint if exists tickets_warranty_days_check,
    add constraint tickets_warranty_days_check
        check (warranty_days is null or warranty_days between 1 and 730),
    drop constraint if exists tickets_warranty_dates_check,
    add constraint tickets_warranty_dates_check
        check (
            warranty_start_at is null
            or warranty_expires_at is null
            or warranty_expires_at >= warranty_start_at
        ),
    drop constraint if exists tickets_warranty_shape_check,
    add constraint tickets_warranty_shape_check
        check (
            (
                warranty_claim
                and warranty_origin_ticket_id is not null
                and warranty_source_claim_id is null
                and warranty_status is not null
            )
            or (
                not warranty_claim
                and warranty_status is null
                and warranty_technical_report is null
                and warranty_needs_parts is null
                and warranty_decided_at is null
                and warranty_decided_by is null
                and warranty_decided_by_name is null
            )
        );

alter table public.tickets
    drop constraint if exists tickets_warranty_origin_ticket_id_fkey,
    add constraint tickets_warranty_origin_ticket_id_fkey
        foreign key (warranty_origin_ticket_id)
        references public.tickets(id)
        on delete restrict,
    drop constraint if exists tickets_warranty_source_claim_id_fkey,
    add constraint tickets_warranty_source_claim_id_fkey
        foreign key (warranty_source_claim_id)
        references public.tickets(id)
        on delete restrict,
    drop constraint if exists tickets_warranty_converted_ticket_id_fkey,
    add constraint tickets_warranty_converted_ticket_id_fkey
        foreign key (warranty_converted_ticket_id)
        references public.tickets(id)
        on delete restrict;

create index if not exists idx_tickets_warranty_origin_active
    on public.tickets (workspace_id, warranty_origin_ticket_id, status)
    where deleted_at is null and warranty_claim;

create unique index if not exists idx_tickets_warranty_source_claim_unique
    on public.tickets (warranty_source_claim_id)
    where deleted_at is null and warranty_source_claim_id is not null;

create index if not exists idx_tickets_warranty_coverage
    on public.tickets (workspace_id, customer_id, delivered_at desc, id)
    where deleted_at is null and not warranty_claim and repair_successful is true;

create or replace function public.aida_warranty_days()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
    with ctx as (
        select workspace_id from public.get_current_actor_context()
    )
    select greatest(
        1,
        least(
            730,
            case
                when coalesce(w.tracker_config -> 'workflow' ->> 'warranty_days', '') ~ '^[0-9]+$'
                    then (w.tracker_config -> 'workflow' ->> 'warranty_days')::integer
                else 90
            end
        )
    )
    from public.workspaces w
    join ctx on ctx.workspace_id = w.id;
$$;

create or replace function public.aida_warranty_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    with ctx as (
        select workspace_id from public.get_current_actor_context()
    )
    select
        case
            when coalesce((w.tracker_config -> 'customization' ->> 'workflow')::boolean, false)
                then coalesce((w.tracker_config -> 'workflow' ->> 'warranty_control')::boolean, true)
            else true
        end
        and
        case
            when coalesce((w.tracker_config -> 'customization' ->> 'modules')::boolean, false)
                then coalesce((w.tracker_config -> 'modules' ->> 'customers')::boolean, true)
            else true
        end
    from public.workspaces w
    join ctx on ctx.workspace_id = w.id;
$$;

create or replace function public.aida_warranty_parts_control_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    with ctx as (
        select workspace_id from public.get_current_actor_context()
    )
    select
        case
            when coalesce((w.tracker_config -> 'customization' ->> 'workflow')::boolean, false)
                then coalesce((w.tracker_config -> 'workflow' ->> 'parts_control')::boolean, true)
            else true
        end
    from public.workspaces w
    join ctx on ctx.workspace_id = w.id;
$$;

revoke all on function public.aida_warranty_days() from public;
revoke all on function public.aida_warranty_enabled() from public;
revoke all on function public.aida_warranty_parts_control_enabled() from public;
grant execute on function public.aida_warranty_days() to anon, authenticated;
grant execute on function public.aida_warranty_enabled() to anon, authenticated;
grant execute on function public.aida_warranty_parts_control_enabled() to anon, authenticated;

create or replace function private.validate_warranty_tracker_config()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_enabled jsonb;
    v_days jsonb;
    v_days_value integer;
begin
    v_enabled := new.tracker_config -> 'workflow' -> 'warranty_control';
    if v_enabled is not null and jsonb_typeof(v_enabled) <> 'boolean' then
        raise exception 'Controle de garantia deve ser verdadeiro ou falso.';
    end if;

    v_days := new.tracker_config -> 'workflow' -> 'warranty_days';
    if v_days is not null then
        if jsonb_typeof(v_days) <> 'number' or (v_days #>> '{}') !~ '^[0-9]+$' then
            raise exception 'O prazo de garantia deve ser um numero inteiro.';
        end if;
        v_days_value := (v_days #>> '{}')::integer;
        if v_days_value < 1 or v_days_value > 730 then
            raise exception 'O prazo de garantia deve estar entre 1 e 730 dias.';
        end if;
    end if;

  return new;
end;
$$;

revoke all on function private.validate_warranty_tracker_config() from public;

drop trigger if exists aida_validate_warranty_tracker_config on public.workspaces;
create trigger aida_validate_warranty_tracker_config
before insert or update of tracker_config on public.workspaces
for each row execute function private.validate_warranty_tracker_config();

create or replace function private.adopt_legacy_warranty_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_origin public.tickets%rowtype;
    v_customer public.customers%rowtype;
begin
    if not new.warranty_claim or new.warranty_origin_ticket_id is null then
        return new;
    end if;

    select * into v_ctx from public.get_current_actor_context();
    if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false))
       or new.workspace_id is distinct from v_ctx.workspace_id then
        raise exception 'Acesso negado ao vinculo do cliente da garantia.';
    end if;

    select *
      into v_origin
      from public.tickets t
     where t.id = new.warranty_origin_ticket_id
       and t.workspace_id = new.workspace_id
       and t.deleted_at is null
     for update;

    if not found or v_origin.customer_id is not null then
        return new;
    end if;
    if new.customer_id is null then
        raise exception 'Cadastre ou selecione o cliente antes de abrir a garantia.';
    end if;

    select *
      into v_customer
      from public.customers c
     where c.id = new.customer_id
       and c.workspace_id = new.workspace_id
       and c.deleted_at is null;

    if not found
       or lower(btrim(v_customer.name)) <> lower(btrim(v_origin.client_name)) then
        raise exception 'O cliente selecionado deve corresponder ao nome registrado na OS original.';
    end if;

    update public.tickets
       set customer_id = v_customer.id
     where id = v_origin.id
       and workspace_id = new.workspace_id
       and customer_id is null;

    return new;
end;
$$;

revoke all on function private.adopt_legacy_warranty_customer() from public;

drop trigger if exists aida_adopt_legacy_warranty_customer on public.tickets;
create trigger aida_adopt_legacy_warranty_customer
before insert on public.tickets
for each row execute function private.adopt_legacy_warranty_customer();

create or replace function private.enforce_ticket_warranty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_origin public.tickets%rowtype;
    v_claim public.tickets%rowtype;
    v_days integer;
    v_start timestamptz;
    v_expiry timestamptz;
begin
    select * into v_ctx from public.get_current_actor_context();

    if new.workspace_id is distinct from v_ctx.workspace_id then
        raise exception 'A OS de garantia deve pertencer a empresa atual.';
    end if;

    v_days := coalesce(public.aida_warranty_days(), 90);

    if tg_op = 'INSERT' then
        if new.warranty_claim then
            if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
                raise exception 'Somente administradores e atendentes podem abrir um retorno em garantia.';
            end if;
            if not coalesce(public.aida_warranty_enabled(), true) then
                raise exception 'A abertura de retornos em garantia esta desativada.';
            end if;
            if new.warranty_origin_ticket_id is null then
                raise exception 'Selecione a OS original da garantia.';
            end if;

            select *
              into v_origin
              from public.tickets t
             where t.id = new.warranty_origin_ticket_id
               and t.workspace_id = new.workspace_id
               and t.deleted_at is null
             for share;

            if not found then
                raise exception 'OS original nao encontrada ou fora da empresa.';
            end if;
            if v_origin.warranty_claim then
                raise exception 'A garantia deve ser vinculada a uma OS de servico original.';
            end if;
            if v_origin.customer_id is null or new.customer_id is distinct from v_origin.customer_id then
                raise exception 'O retorno deve usar o mesmo cliente da OS original.';
            end if;
            if v_origin.repair_successful is distinct from true
               or v_origin.delivered_at is null
               or v_origin.status <> 'Finalizado' then
                raise exception 'A OS original precisa estar finalizada, entregue e com reparo concluido com sucesso.';
            end if;

            v_start := coalesce(v_origin.warranty_start_at, v_origin.delivered_at);
            v_expiry := coalesce(
                v_origin.warranty_expires_at,
                v_start + make_interval(days => coalesce(v_origin.warranty_days, v_days))
            );
            if v_expiry < now() then
                raise exception 'A garantia desta OS expirou em %.', to_char(v_expiry at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
            end if;
            if exists (
                select 1
                  from public.tickets active_claim
                 where active_claim.workspace_id = new.workspace_id
                   and active_claim.warranty_claim
                   and active_claim.warranty_origin_ticket_id = v_origin.id
                   and active_claim.deleted_at is null
                   and active_claim.status <> 'Finalizado'
            ) then
                raise exception 'Ja existe um retorno em garantia aberto para esta OS.';
            end if;

            new.customer_id := v_origin.customer_id;
            new.client_name := v_origin.client_name;
            new.contact_info := coalesce(new.contact_info, v_origin.contact_info);
            new.device_model := v_origin.device_model;
            new.serial_number := v_origin.serial_number;
            new.warranty_source_claim_id := null;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := 'pending';
            new.warranty_days := coalesce(v_origin.warranty_days, v_days);
            new.warranty_start_at := v_start;
            new.warranty_expires_at := v_expiry;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        elsif new.warranty_source_claim_id is not null then
            if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
                raise exception 'Somente administradores e atendentes podem converter um retorno em uma nova OS.';
            end if;

            select *
              into v_claim
              from public.tickets t
             where t.id = new.warranty_source_claim_id
               and t.workspace_id = new.workspace_id
               and t.deleted_at is null
             for share;

            if not found or not v_claim.warranty_claim or v_claim.warranty_status <> 'not_covered' then
                raise exception 'O retorno informado nao esta aguardando uma nova OS paga.';
            end if;
            if v_claim.customer_id is null or new.customer_id is distinct from v_claim.customer_id then
                raise exception 'A nova OS deve usar o mesmo cliente do retorno.';
            end if;
            if v_claim.warranty_converted_ticket_id is not null then
                raise exception 'Este retorno ja foi convertido em uma nova OS.';
            end if;

            new.warranty_claim := false;
            new.warranty_origin_ticket_id := v_claim.warranty_origin_ticket_id;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := null;
            new.warranty_days := null;
            new.warranty_start_at := null;
            new.warranty_expires_at := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        else
            new.warranty_claim := false;
            new.warranty_origin_ticket_id := null;
            new.warranty_converted_ticket_id := null;
            new.warranty_status := null;
            new.warranty_days := null;
            new.warranty_start_at := null;
            new.warranty_expires_at := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        end if;
    else
        if old.warranty_claim is distinct from new.warranty_claim
           or old.warranty_origin_ticket_id is distinct from new.warranty_origin_ticket_id
           or old.warranty_source_claim_id is distinct from new.warranty_source_claim_id then
            raise exception 'Os vinculos da garantia nao podem ser alterados depois da abertura.';
        end if;

        if old.warranty_converted_ticket_id is distinct from new.warranty_converted_ticket_id
           and not (
                old.warranty_claim
                and old.warranty_status = 'not_covered'
                and old.warranty_converted_ticket_id is null
                and new.warranty_converted_ticket_id is not null
                and (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false))
           ) then
            raise exception 'O vinculo da nova OS paga e protegido.';
        end if;

        if old.warranty_claim then
            if new.warranty_status is distinct from old.warranty_status then
                if old.warranty_status <> 'pending'
                   or new.warranty_status not in ('covered', 'not_covered')
                   or old.status <> 'Analise Tecnica' then
                    raise exception 'Decisao de garantia invalida para a etapa atual.';
                end if;
                if not (
                    coalesce(v_ctx.is_admin, false)
                    or (
                        coalesce(v_ctx.is_technician, false)
                        and old.technician_id = v_ctx.actor_employee_id
                    )
                ) then
                    raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a analise da garantia.';
                end if;
                if length(btrim(coalesce(new.warranty_technical_report, ''))) < 20 then
                    raise exception 'Preencha um laudo tecnico com pelo menos 20 caracteres.';
                end if;
                if coalesce(new.warranty_needs_parts, false)
                   and length(btrim(coalesce(new.parts_needed, ''))) < 2 then
                    raise exception 'Informe as pecas necessarias.';
                end if;
                if coalesce(new.warranty_needs_parts, false)
                   and not coalesce(public.aida_warranty_parts_control_enabled(), true) then
                    raise exception 'O controle de compra de pecas esta desativado.';
                end if;

                new.warranty_decided_at := now();
                new.warranty_decided_by := coalesce(v_ctx.actor_employee_id, v_ctx.actor_user_id);
                new.warranty_decided_by_name := v_ctx.actor_name;
            elsif new.warranty_status = 'pending' then
                new.warranty_technical_report := null;
                new.warranty_needs_parts := null;
                new.warranty_decided_at := null;
                new.warranty_decided_by := null;
                new.warranty_decided_by_name := null;
            end if;
        else
            new.warranty_status := null;
            new.warranty_technical_report := null;
            new.warranty_needs_parts := null;
            new.warranty_decided_at := null;
            new.warranty_decided_by := null;
            new.warranty_decided_by_name := null;
        end if;
    end if;

    -- A successful paid service starts its own warranty when it is delivered.
    -- Warranty claims never reset or extend the original coverage.
    if not new.warranty_claim
       and new.repair_successful is true
       and new.delivered_at is not null then
        new.warranty_days := case
            when tg_op = 'UPDATE' then coalesce(old.warranty_days, v_days)
            else v_days
        end;
        new.warranty_start_at := new.delivered_at;
        new.warranty_expires_at := new.delivered_at + make_interval(days => new.warranty_days);
    end if;

  return new;
end;
$$;

revoke all on function private.enforce_ticket_warranty() from public;

drop trigger if exists aida_enforce_ticket_warranty on public.tickets;
create trigger aida_enforce_ticket_warranty
before insert or update of
    workspace_id, customer_id, status, repair_successful, delivered_at,
    warranty_claim, warranty_origin_ticket_id, warranty_source_claim_id,
    warranty_converted_ticket_id, warranty_status, warranty_days,
    warranty_start_at, warranty_expires_at, warranty_technical_report,
    warranty_needs_parts, warranty_decided_at, warranty_decided_by,
    warranty_decided_by_name
on public.tickets
for each row execute function private.enforce_ticket_warranty();

create or replace function public.get_warranty_eligible_tickets(
    p_customer_id uuid,
    p_search text default null,
    p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_search text := nullif(btrim(coalesce(p_search, '')), '');
    v_days integer;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Acesso negado aos retornos em garantia.';
    end if;
    if not coalesce(public.aida_warranty_enabled(), true) then
        raise exception 'A abertura de retornos em garantia esta desativada.';
    end if;
    if p_customer_id is null then
        raise exception 'Selecione o cliente.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;
    if not exists (
        select 1
          from public.customers c
         where c.id = p_customer_id
           and c.workspace_id = v_ctx.workspace_id
           and c.deleted_at is null
    ) then
        raise exception 'Cliente nao encontrado ou fora da empresa.';
    end if;

    v_days := coalesce(public.aida_warranty_days(), 90);

    with candidates as (
        select
            t.id,
            t.customer_id,
            t.os_number,
            t.client_name,
            t.contact_info,
            t.device_model,
            t.serial_number,
            t.defect_reported,
            t.technician_id,
            t.delivered_at,
            coalesce(t.warranty_days, v_days) as warranty_days,
            coalesce(t.warranty_start_at, t.delivered_at) as warranty_start_at,
            coalesce(
                t.warranty_expires_at,
                t.delivered_at + make_interval(days => coalesce(t.warranty_days, v_days))
            ) as warranty_expires_at,
            exists (
                select 1
                  from public.tickets claim
                 where claim.workspace_id = t.workspace_id
                   and claim.warranty_claim
                   and claim.warranty_origin_ticket_id = t.id
                   and claim.deleted_at is null
                   and claim.status <> 'Finalizado'
            ) as has_open_claim
        from public.tickets t
        where t.workspace_id = v_ctx.workspace_id
          and t.customer_id = p_customer_id
          and t.deleted_at is null
          and not t.warranty_claim
          and t.status = 'Finalizado'
          and t.delivered_at is not null
          and t.repair_successful is true
          and (
              v_search is null
              or t.os_number ilike '%' || v_search || '%'
              or t.device_model ilike '%' || v_search || '%'
              or coalesce(t.serial_number, '') ilike '%' || v_search || '%'
          )
        order by t.delivered_at desc, t.id desc
        limit p_limit
    )
    select jsonb_build_object(
        'items',
        coalesce(
            jsonb_agg(
                to_jsonb(c)
                || jsonb_build_object(
                    'eligible', c.warranty_expires_at >= now() and not c.has_open_claim,
                    'eligibility_reason',
                    case
                        when c.has_open_claim then 'Ja existe um retorno aberto'
                        when c.warranty_expires_at < now() then 'Garantia expirada'
                        else 'Dentro da garantia'
                    end
                )
                order by c.delivered_at desc, c.id desc
            ),
            '[]'::jsonb
        )
    )
      into v_result
      from candidates c;

    return coalesce(v_result, jsonb_build_object('items', '[]'::jsonb));
end;
$$;

create or replace function public.get_warranty_ticket_summaries(p_ticket_ids uuid[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_days integer;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket_ids is null or cardinality(p_ticket_ids) = 0 then
        return '[]'::jsonb;
    end if;
    if cardinality(p_ticket_ids) > 50 then
        raise exception 'No maximo 50 OS podem ser consultadas por vez.';
    end if;

    v_days := coalesce(public.aida_warranty_days(), 90);

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id', t.id,
                'warranty_claim', t.warranty_claim,
                'warranty_origin_ticket_id', t.warranty_origin_ticket_id,
                'warranty_source_claim_id', t.warranty_source_claim_id,
                'warranty_converted_ticket_id', t.warranty_converted_ticket_id,
                'warranty_status', t.warranty_status,
                'warranty_days', coalesce(t.warranty_days, v_days),
                'warranty_start_at', coalesce(t.warranty_start_at, t.delivered_at),
                'warranty_expires_at', coalesce(
                    t.warranty_expires_at,
                    case
                        when t.delivered_at is not null
                            then t.delivered_at + make_interval(days => coalesce(t.warranty_days, v_days))
                    end
                ),
                'warranty_needs_parts', t.warranty_needs_parts,
                'warranty_decided_at', t.warranty_decided_at,
                'warranty_decided_by_name', t.warranty_decided_by_name
            )
        ),
        '[]'::jsonb
    )
      into v_result
      from public.tickets t
     where t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null
       and t.id = any(p_ticket_ids);

    return v_result;
end;
$$;

create or replace function public.complete_warranty_analysis(
    p_ticket_id uuid,
    p_covered boolean,
    p_report text,
    p_needs_parts boolean default false,
    p_parts text default null,
    p_tech_notes text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_parts_enabled boolean;
    v_target_status text;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_ticket_id is null or p_covered is null then
        raise exception 'Informe a OS e a decisao da garantia.';
    end if;
    if length(btrim(coalesce(p_report, ''))) < 20 then
        raise exception 'Preencha um laudo tecnico com pelo menos 20 caracteres.';
    end if;

    select *
      into v_ticket
      from public.tickets t
     where t.id = p_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null
     for update;

    if not found or not v_ticket.warranty_claim or v_ticket.warranty_status <> 'pending' then
        raise exception 'Este retorno nao esta aguardando a decisao da garantia.';
    end if;
    if v_ticket.status <> 'Analise Tecnica' then
        raise exception 'A decisao da garantia so pode ser registrada durante a analise tecnica.';
    end if;
    if not (
        coalesce(v_ctx.is_admin, false)
        or (
            coalesce(v_ctx.is_technician, false)
            and v_ticket.technician_id = v_ctx.actor_employee_id
        )
    ) then
        raise exception 'Somente o tecnico responsavel ou um administrador pode concluir a analise.';
    end if;

    v_parts_enabled := coalesce(public.aida_warranty_parts_control_enabled(), true);

    if coalesce(p_needs_parts, false) and not coalesce(v_parts_enabled, true) then
        raise exception 'O controle de compra de pecas esta desativado.';
    end if;
    if coalesce(p_needs_parts, false) and length(btrim(coalesce(p_parts, ''))) < 2 then
        raise exception 'Informe as pecas necessarias.';
    end if;

    v_target_status := case
        when not p_covered then 'Aprovacao'
        when coalesce(p_needs_parts, false) then 'Compra Peca'
        else 'Andamento Reparo'
    end;

    update public.tickets t
       set warranty_status = case when p_covered then 'covered' else 'not_covered' end,
           warranty_technical_report = btrim(p_report),
           warranty_needs_parts = coalesce(p_needs_parts, false),
           parts_needed = case when coalesce(p_needs_parts, false) then btrim(p_parts) else null end,
           parts_status = case when coalesce(p_needs_parts, false) then 'Pendente' else 'N/A' end,
           budget_status = case when p_covered then 'Aprovado' else 'Pendente' end,
           tech_notes = coalesce(p_tech_notes, t.tech_notes),
           previous_status = t.status,
           status = v_target_status,
           updated_at = now()
     where t.id = v_ticket.id
     returning * into v_ticket;

    return to_jsonb(v_ticket);
end;
$$;

create or replace function public.link_warranty_paid_ticket(
    p_claim_ticket_id uuid,
    p_paid_ticket_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_claim public.tickets%rowtype;
    v_paid public.tickets%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Somente administradores e atendentes podem concluir a conversao.';
    end if;

    select *
      into v_claim
      from public.tickets t
     where t.id = p_claim_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null
     for update;

    if not found then
        raise exception 'Retorno em garantia nao encontrado.';
    end if;

    select *
      into v_paid
      from public.tickets t
     where t.id = p_paid_ticket_id
       and t.workspace_id = v_ctx.workspace_id
       and t.deleted_at is null;

    if not found then
        raise exception 'Nova OS paga nao encontrada.';
    end if;
    if not v_claim.warranty_claim or v_claim.warranty_status <> 'not_covered' then
        raise exception 'O retorno nao esta disponivel para conversao.';
    end if;
    if v_claim.warranty_converted_ticket_id is not null then
        raise exception 'Este retorno ja foi convertido.';
    end if;
    if v_paid.warranty_source_claim_id is distinct from v_claim.id
       or v_paid.customer_id is distinct from v_claim.customer_id then
        raise exception 'A nova OS nao possui o vinculo esperado com o retorno.';
    end if;

    update public.tickets t
       set warranty_converted_ticket_id = v_paid.id,
           previous_status = t.status,
           status = 'Finalizado',
           budget_status = 'Aprovado',
           repair_successful = false,
           delivered_at = now(),
           updated_at = now()
     where t.id = v_claim.id
     returning * into v_claim;

    return to_jsonb(v_claim);
end;
$$;

revoke all on function public.get_warranty_eligible_tickets(uuid, text, integer) from public;
revoke all on function public.get_warranty_ticket_summaries(uuid[]) from public;
revoke all on function public.complete_warranty_analysis(uuid, boolean, text, boolean, text, text) from public;
revoke all on function public.link_warranty_paid_ticket(uuid, uuid) from public;

grant execute on function public.get_warranty_eligible_tickets(uuid, text, integer) to anon, authenticated;
grant execute on function public.get_warranty_ticket_summaries(uuid[]) to anon, authenticated;
grant execute on function public.complete_warranty_analysis(uuid, boolean, text, boolean, text, text) to anon, authenticated;
grant execute on function public.link_warranty_paid_ticket(uuid, uuid) to anon, authenticated;

comment on function public.get_warranty_eligible_tickets(uuid, text, integer)
is 'Returns a bounded RLS-protected list of successful delivered OS eligible for a customer warranty return.';
comment on function public.get_warranty_ticket_summaries(uuid[])
is 'Hydrates only warranty metadata for up to 50 already visible ticket cards.';
comment on function public.complete_warranty_analysis(uuid, boolean, text, boolean, text, text)
is 'Records the protected technical warranty decision and advances through the existing workflow.';
comment on function public.link_warranty_paid_ticket(uuid, uuid)
is 'Finalizes a rejected warranty evaluation after a linked normal paid OS has been created.';

commit;
