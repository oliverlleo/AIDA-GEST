-- Cadastro de clientes com isolamento por empresa, consultas paginadas e
-- vinculo opcional com OS. Nao ha backfill: OS antigas continuam sem customer_id.

begin;

create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    name text not null,
    preferred_name text,
    person_type text,
    document_number text,
    state_registration text,
    phone text,
    whatsapp text,
    email text,
    birth_date date,
    postal_code text,
    address_line text,
    address_number text,
    address_complement text,
    neighborhood text,
    city text,
    state text,
    country text,
    notes text,
    created_by uuid,
    created_by_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint customers_name_nonblank_check check (btrim(name) <> ''),
    constraint customers_workspace_id_fkey
        foreign key (workspace_id) references public.workspaces(id) on delete restrict,
    constraint customers_workspace_id_id_key unique (workspace_id, id)
);

alter table public.customers
    add column if not exists preferred_name text,
    add column if not exists person_type text,
    add column if not exists document_number text,
    add column if not exists state_registration text,
    add column if not exists phone text,
    add column if not exists whatsapp text,
    add column if not exists email text,
    add column if not exists birth_date date,
    add column if not exists postal_code text,
    add column if not exists address_line text,
    add column if not exists address_number text,
    add column if not exists address_complement text,
    add column if not exists neighborhood text,
    add column if not exists city text,
    add column if not exists state text,
    add column if not exists country text,
    add column if not exists notes text,
    add column if not exists created_by uuid,
    add column if not exists created_by_name text,
    add column if not exists created_at timestamptz not null default now(),
    add column if not exists updated_at timestamptz not null default now(),
    add column if not exists deleted_at timestamptz;

do $customer_constraints$
begin
    if not exists (
        select 1
          from pg_constraint
         where conrelid = 'public.customers'::regclass
           and conname = 'customers_name_nonblank_check'
    ) then
        alter table public.customers
            add constraint customers_name_nonblank_check
            check (btrim(name) <> '') not valid;
    end if;

    if not exists (
        select 1
          from pg_constraint
         where conrelid = 'public.customers'::regclass
           and conname = 'customers_workspace_id_fkey'
    ) then
        alter table public.customers
            add constraint customers_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1
          from pg_constraint
         where conrelid = 'public.customers'::regclass
           and conname = 'customers_workspace_id_id_key'
    ) then
        alter table public.customers
            add constraint customers_workspace_id_id_key unique (workspace_id, id);
    end if;
end
$customer_constraints$;

create index if not exists customers_workspace_active_name_idx
    on public.customers (workspace_id, lower(name), id)
    where deleted_at is null;

create index if not exists customers_workspace_document_idx
    on public.customers (workspace_id, document_number)
    where deleted_at is null and document_number is not null;

alter table public.tickets
    add column if not exists customer_id uuid;

do $ticket_customer_constraint$
begin
    if not exists (
        select 1
          from pg_constraint
         where conrelid = 'public.tickets'::regclass
           and conname = 'tickets_workspace_customer_fkey'
    ) then
        alter table public.tickets
            add constraint tickets_workspace_customer_fkey
            foreign key (workspace_id, customer_id)
            references public.customers(workspace_id, id)
            on delete restrict not valid;
    end if;
end
$ticket_customer_constraint$;

create index if not exists tickets_workspace_customer_created_idx
    on public.tickets (workspace_id, customer_id, created_at desc, id desc)
    where customer_id is not null;

alter table public.customers enable row level security;
alter table public.customers force row level security;

create or replace function public.aida_customers_enabled()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_config jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if v_ctx.workspace_id is null
       or not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        return false;
    end if;

    select coalesce(w.tracker_config, '{}'::jsonb)
      into v_config
      from public.workspaces w
     where w.id = v_ctx.workspace_id;

    return not (
        lower(coalesce(v_config -> 'customization' ->> 'modules', 'false')) = 'true'
        and lower(coalesce(v_config -> 'modules' ->> 'customers', 'true')) = 'false'
    );
end;
$$;

drop policy if exists customers_select_admin_attendant on public.customers;
drop policy if exists customers_insert_admin_attendant on public.customers;
drop policy if exists customers_update_admin_attendant on public.customers;

create policy customers_select_admin_attendant
on public.customers
as permissive
for select
to anon, authenticated
using (
    workspace_id = (
        select ctx.workspace_id
          from public.get_current_actor_context() ctx
    )
    and (
        select ctx.is_admin or ctx.is_attendant
          from public.get_current_actor_context() ctx
    )
    and (select public.aida_customers_enabled())
);

create policy customers_insert_admin_attendant
on public.customers
as permissive
for insert
to anon, authenticated
with check (
    workspace_id = (
        select ctx.workspace_id
          from public.get_current_actor_context() ctx
    )
    and (
        select ctx.is_admin or ctx.is_attendant
          from public.get_current_actor_context() ctx
    )
    and (select public.aida_customers_enabled())
);

create policy customers_update_admin_attendant
on public.customers
as permissive
for update
to anon, authenticated
using (
    workspace_id = (
        select ctx.workspace_id
          from public.get_current_actor_context() ctx
    )
    and (
        select ctx.is_admin or ctx.is_attendant
          from public.get_current_actor_context() ctx
    )
    and (select public.aida_customers_enabled())
)
with check (
    workspace_id = (
        select ctx.workspace_id
          from public.get_current_actor_context() ctx
    )
    and (
        select ctx.is_admin or ctx.is_attendant
          from public.get_current_actor_context() ctx
    )
    and (select public.aida_customers_enabled())
);

create or replace function public.aida_enforce_customer_identity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
begin
    if current_user not in ('anon', 'authenticated') then
        new.updated_at := now();
        return new;
    end if;

    select * into v_ctx from public.get_current_actor_context();

    if v_ctx.workspace_id is null
       or not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Acesso negado ao cadastro de clientes.';
    end if;

    if tg_op = 'INSERT' then
        new.workspace_id := v_ctx.workspace_id;
        new.created_by := coalesce(v_ctx.actor_employee_id, v_ctx.actor_user_id);
        new.created_by_name := v_ctx.actor_name;
        new.created_at := coalesce(new.created_at, now());
    elsif new.id is distinct from old.id
       or new.workspace_id is distinct from old.workspace_id
       or new.created_by is distinct from old.created_by
       or new.created_by_name is distinct from old.created_by_name
       or new.created_at is distinct from old.created_at then
        raise exception 'Acesso negado: identidade e empresa do cliente nao podem ser alteradas.';
    end if;

    new.name := btrim(new.name);
    new.preferred_name := nullif(btrim(new.preferred_name), '');
    new.person_type := lower(nullif(btrim(new.person_type), ''));
    new.document_number := nullif(btrim(new.document_number), '');
    new.state_registration := nullif(btrim(new.state_registration), '');
    new.phone := nullif(btrim(new.phone), '');
    new.whatsapp := nullif(btrim(new.whatsapp), '');
    new.email := nullif(btrim(new.email), '');
    new.postal_code := nullif(btrim(new.postal_code), '');
    new.address_line := nullif(btrim(new.address_line), '');
    new.address_number := nullif(btrim(new.address_number), '');
    new.address_complement := nullif(btrim(new.address_complement), '');
    new.neighborhood := nullif(btrim(new.neighborhood), '');
    new.city := nullif(btrim(new.city), '');
    new.state := nullif(btrim(new.state), '');
    new.country := nullif(btrim(new.country), '');
    new.notes := nullif(btrim(new.notes), '');

    if new.name is null or new.name = '' then
        raise exception 'Informe o nome do cliente.';
    end if;
    if new.person_type is not null and new.person_type not in ('person', 'company') then
        raise exception 'Tipo de cliente invalido.';
    end if;
    if length(new.name) > 200
       or length(coalesce(new.preferred_name, '')) > 200
       or length(coalesce(new.document_number, '')) > 40
       or length(coalesce(new.state_registration, '')) > 40
       or length(coalesce(new.phone, '')) > 40
       or length(coalesce(new.whatsapp, '')) > 40
       or length(coalesce(new.email, '')) > 254
       or length(coalesce(new.postal_code, '')) > 20
       or length(coalesce(new.address_line, '')) > 300
       or length(coalesce(new.address_number, '')) > 40
       or length(coalesce(new.address_complement, '')) > 200
       or length(coalesce(new.neighborhood, '')) > 150
       or length(coalesce(new.city, '')) > 150
       or length(coalesce(new.state, '')) > 100
       or length(coalesce(new.country, '')) > 100
       or length(coalesce(new.notes, '')) > 10000 then
        raise exception 'Um ou mais campos do cliente excedem o tamanho permitido.';
    end if;

    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists aida_enforce_customer_identity on public.customers;
create trigger aida_enforce_customer_identity
before insert or update on public.customers
for each row execute function public.aida_enforce_customer_identity();

create or replace function public.aida_enforce_ticket_customer_link()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_customer record;
    v_link_changed boolean;
begin
    if current_user not in ('anon', 'authenticated') then
        return new;
    end if;

    select * into v_ctx from public.get_current_actor_context();
    v_link_changed := tg_op = 'INSERT'
        and new.customer_id is not null
        or tg_op = 'UPDATE'
        and new.customer_id is distinct from old.customer_id;

    if not v_link_changed then
        return new;
    end if;

    if v_ctx.workspace_id is null
       or not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Acesso negado: este cargo nao pode trocar o cliente da OS.';
    end if;

    if not public.aida_customers_enabled() then
        raise exception 'O cadastro de clientes esta desativado.';
    end if;

    if new.customer_id is null then
        return new;
    end if;

    select c.id, c.name, c.phone, c.whatsapp, c.email
      into v_customer
      from public.customers c
     where c.id = new.customer_id
       and c.workspace_id = v_ctx.workspace_id
       and c.deleted_at is null;

    if not found then
        raise exception 'Cliente nao encontrado ou fora da empresa.';
    end if;

    new.workspace_id := v_ctx.workspace_id;
    new.client_name := v_customer.name;
    new.contact_info := coalesce(
        nullif(btrim(new.contact_info), ''),
        nullif(btrim(v_customer.whatsapp), ''),
        nullif(btrim(v_customer.phone), ''),
        nullif(btrim(v_customer.email), '')
    );
    return new;
end;
$$;

drop trigger if exists aida_enforce_ticket_customer_link on public.tickets;
create trigger aida_enforce_ticket_customer_link
before insert or update of customer_id on public.tickets
for each row execute function public.aida_enforce_ticket_customer_link();

drop function if exists public.get_customer_page(text, integer, jsonb);
create or replace function public.get_customer_page(
    p_search text default null,
    p_limit integer default 20,
    p_cursor jsonb default null,
    p_include_total boolean default true
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
    v_cursor_name text;
    v_cursor_id uuid;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if v_ctx.workspace_id is null
       or not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Acesso negado ao cadastro de clientes.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;

    if not public.aida_customers_enabled() then
        raise exception 'O cadastro de clientes esta desativado.';
    end if;

    if p_cursor is not null then
        begin
            v_cursor_name := p_cursor ->> 'name';
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de paginacao invalido.';
        end;
        if v_cursor_name is null or v_cursor_id is null then
            raise exception 'Cursor de paginacao incompleto.';
        end if;
    end if;

    with base as not materialized (
        select
            c.id,
            c.name,
            c.preferred_name,
            c.person_type,
            c.document_number,
            c.state_registration,
            c.phone,
            c.whatsapp,
            c.email,
            c.birth_date,
            c.postal_code,
            c.address_line,
            c.address_number,
            c.address_complement,
            c.neighborhood,
            c.city,
            c.state,
            c.country,
            c.notes,
            c.created_at,
            c.updated_at,
            lower(c.name) as name_sort
        from public.customers c
        where c.workspace_id = v_ctx.workspace_id
          and c.deleted_at is null
          and (
              v_search is null
              or c.name ilike '%' || v_search || '%'
              or coalesce(c.preferred_name, '') ilike '%' || v_search || '%'
              or coalesce(c.document_number, '') ilike '%' || v_search || '%'
              or coalesce(c.phone, '') ilike '%' || v_search || '%'
              or coalesce(c.whatsapp, '') ilike '%' || v_search || '%'
              or coalesce(c.email, '') ilike '%' || v_search || '%'
              or coalesce(c.state_registration, '') ilike '%' || v_search || '%'
              or coalesce(c.birth_date::text, '') ilike '%' || v_search || '%'
              or coalesce(c.postal_code, '') ilike '%' || v_search || '%'
              or coalesce(c.address_line, '') ilike '%' || v_search || '%'
              or coalesce(c.address_number, '') ilike '%' || v_search || '%'
              or coalesce(c.address_complement, '') ilike '%' || v_search || '%'
              or coalesce(c.neighborhood, '') ilike '%' || v_search || '%'
              or coalesce(c.city, '') ilike '%' || v_search || '%'
              or coalesce(c.state, '') ilike '%' || v_search || '%'
              or coalesce(c.country, '') ilike '%' || v_search || '%'
              or coalesce(c.notes, '') ilike '%' || v_search || '%'
          )
    ), filtered as (
        select *
          from base b
         where p_cursor is null
            or (b.name_sort, b.id) > (v_cursor_name, v_cursor_id)
    ), page_plus_one as materialized (
        select *
          from filtered
         order by name_sort, id
         limit p_limit + 1
    ), page_rows as materialized (
        select *
          from page_plus_one
         order by name_sort, id
         limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(
                (to_jsonb(p) - 'name_sort')
                || jsonb_build_object(
                    '_card_summary', true,
                    'ticket_count', (
                        select count(*)
                          from public.tickets t
                         where t.workspace_id = v_ctx.workspace_id
                           and t.customer_id = p.id
                           and t.deleted_at is null
                    )
                )
                order by p.name_sort, p.id
            )
              from page_rows p
        ), '[]'::jsonb),
        'total', case
            when coalesce(p_include_total, true) then (select count(*) from base)
            else null
        end,
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (
            select jsonb_build_object('name', p.name_sort, 'id', p.id)
              from page_rows p
             order by p.name_sort desc, p.id desc
             limit 1
        )
    ) into v_result;

    return v_result;
end;
$$;

drop function if exists public.get_customer_ticket_page(uuid, text, integer, jsonb);
create or replace function public.get_customer_ticket_page(
    p_customer_id uuid,
    p_search text default null,
    p_limit integer default 20,
    p_cursor jsonb default null,
    p_include_total boolean default true
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
    v_cursor_created timestamptz;
    v_cursor_id uuid;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if v_ctx.workspace_id is null
       or not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Acesso negado ao cadastro de clientes.';
    end if;
    if p_customer_id is null then
        raise exception 'Informe o cliente.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;

    if not public.aida_customers_enabled() then
        raise exception 'O cadastro de clientes esta desativado.';
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

    if p_cursor is not null then
        begin
            v_cursor_created := (p_cursor ->> 'created_at')::timestamptz;
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de paginacao invalido.';
        end;
        if v_cursor_created is null or v_cursor_id is null then
            raise exception 'Cursor de paginacao incompleto.';
        end if;
    end if;

    with base as not materialized (
        select
            t.id,
            t.os_number,
            t.status,
            t.device_model,
            t.serial_number,
            t.device_condition,
            t.defect_reported,
            t.repair_successful,
            t.repair_end_at,
            t.budget_status,
            t.public_token,
            t.entry_date,
            t.created_at,
            t.updated_at,
            t.delivered_at
        from public.tickets t
        where t.workspace_id = v_ctx.workspace_id
          and t.customer_id = p_customer_id
          and t.deleted_at is null
          and (
              v_search is null
              or t.os_number ilike '%' || v_search || '%'
              or coalesce(t.serial_number, '') ilike '%' || v_search || '%'
              or t.device_model ilike '%' || v_search || '%'
              or coalesce(t.device_condition, '') ilike '%' || v_search || '%'
              or coalesce(t.defect_reported, '') ilike '%' || v_search || '%'
          )
    ), filtered as (
        select *
          from base b
         where p_cursor is null
            or (b.created_at, b.id) < (v_cursor_created, v_cursor_id)
    ), page_plus_one as materialized (
        select *
          from filtered
         order by created_at desc, id desc
         limit p_limit + 1
    ), page_rows as materialized (
        select *
          from page_plus_one
         order by created_at desc, id desc
         limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(
                to_jsonb(p) || jsonb_build_object('_card_summary', true)
                order by p.created_at desc, p.id desc
            )
              from page_rows p
        ), '[]'::jsonb),
        'total', case
            when coalesce(p_include_total, true) then (select count(*) from base)
            else null
        end,
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (
            select jsonb_build_object('created_at', p.created_at, 'id', p.id)
              from page_rows p
             order by p.created_at, p.id
             limit 1
        )
    ) into v_result;

    return v_result;
end;
$$;

create or replace function public.save_customer(p_customer jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_id uuid;
    v_name text;
    v_deleted boolean := false;
    v_saved public.customers%rowtype;
begin
    select * into v_ctx from public.get_current_actor_context();

    if v_ctx.workspace_id is null
       or not (coalesce(v_ctx.is_admin, false) or coalesce(v_ctx.is_attendant, false)) then
        raise exception 'Acesso negado ao cadastro de clientes.';
    end if;
    if p_customer is null or jsonb_typeof(p_customer) <> 'object' then
        raise exception 'Dados do cliente invalidos.';
    end if;

    if not public.aida_customers_enabled() then
        raise exception 'O cadastro de clientes esta desativado.';
    end if;

    begin
        v_id := nullif(p_customer ->> 'id', '')::uuid;
        if p_customer ? 'deleted' then
            v_deleted := (p_customer ->> 'deleted')::boolean;
        end if;
    exception when others then
        raise exception 'Identificador ou acao do cliente invalida.';
    end;

    v_name := nullif(btrim(p_customer ->> 'name'), '');
    if not v_deleted and v_name is null then
        raise exception 'Informe o nome do cliente.';
    end if;
    if length(coalesce(v_name, '')) > 200
       or length(coalesce(p_customer ->> 'preferred_name', '')) > 200
       or length(coalesce(p_customer ->> 'document_number', '')) > 40
       or length(coalesce(p_customer ->> 'phone', '')) > 40
       or length(coalesce(p_customer ->> 'whatsapp', '')) > 40
       or length(coalesce(p_customer ->> 'email', '')) > 254
       or length(coalesce(p_customer ->> 'notes', '')) > 10000 then
        raise exception 'Um ou mais campos do cliente excedem o tamanho permitido.';
    end if;

    if v_id is null then
        if v_deleted then
            raise exception 'Cliente novo nao pode ser excluido.';
        end if;

        insert into public.customers (
            workspace_id, name, preferred_name, person_type, document_number,
            state_registration, phone, whatsapp, email, birth_date, postal_code,
            address_line, address_number, address_complement, neighborhood, city,
            state, country, notes
        ) values (
            v_ctx.workspace_id,
            v_name,
            nullif(btrim(p_customer ->> 'preferred_name'), ''),
            nullif(btrim(p_customer ->> 'person_type'), ''),
            nullif(btrim(p_customer ->> 'document_number'), ''),
            nullif(btrim(p_customer ->> 'state_registration'), ''),
            nullif(btrim(p_customer ->> 'phone'), ''),
            nullif(btrim(p_customer ->> 'whatsapp'), ''),
            nullif(btrim(p_customer ->> 'email'), ''),
            nullif(p_customer ->> 'birth_date', '')::date,
            nullif(btrim(p_customer ->> 'postal_code'), ''),
            nullif(btrim(p_customer ->> 'address_line'), ''),
            nullif(btrim(p_customer ->> 'address_number'), ''),
            nullif(btrim(p_customer ->> 'address_complement'), ''),
            nullif(btrim(p_customer ->> 'neighborhood'), ''),
            nullif(btrim(p_customer ->> 'city'), ''),
            nullif(btrim(p_customer ->> 'state'), ''),
            nullif(btrim(p_customer ->> 'country'), ''),
            nullif(btrim(p_customer ->> 'notes'), '')
        )
        returning * into v_saved;
    elsif v_deleted then
        update public.customers c
           set deleted_at = now()
         where c.id = v_id
           and c.workspace_id = v_ctx.workspace_id
           and c.deleted_at is null
        returning c.* into v_saved;
    else
        update public.customers c
           set name = v_name,
               preferred_name = nullif(btrim(p_customer ->> 'preferred_name'), ''),
               person_type = nullif(btrim(p_customer ->> 'person_type'), ''),
               document_number = nullif(btrim(p_customer ->> 'document_number'), ''),
               state_registration = nullif(btrim(p_customer ->> 'state_registration'), ''),
               phone = nullif(btrim(p_customer ->> 'phone'), ''),
               whatsapp = nullif(btrim(p_customer ->> 'whatsapp'), ''),
               email = nullif(btrim(p_customer ->> 'email'), ''),
               birth_date = nullif(p_customer ->> 'birth_date', '')::date,
               postal_code = nullif(btrim(p_customer ->> 'postal_code'), ''),
               address_line = nullif(btrim(p_customer ->> 'address_line'), ''),
               address_number = nullif(btrim(p_customer ->> 'address_number'), ''),
               address_complement = nullif(btrim(p_customer ->> 'address_complement'), ''),
               neighborhood = nullif(btrim(p_customer ->> 'neighborhood'), ''),
               city = nullif(btrim(p_customer ->> 'city'), ''),
               state = nullif(btrim(p_customer ->> 'state'), ''),
               country = nullif(btrim(p_customer ->> 'country'), ''),
               notes = nullif(btrim(p_customer ->> 'notes'), '')
         where c.id = v_id
           and c.workspace_id = v_ctx.workspace_id
           and c.deleted_at is null
        returning c.* into v_saved;
    end if;

    if not found then
        raise exception 'Cliente nao encontrado ou fora da empresa.';
    end if;

    return to_jsonb(v_saved);
exception
    when invalid_datetime_format or datetime_field_overflow then
        raise exception 'Data de nascimento invalida.';
end;
$$;

-- Mantem a chave customers ativa por padrao e preserva chaves desconhecidas
-- enviadas por versoes futuras do front-end.
create or replace function public.update_workspace_tracker_config(p_config jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_config jsonb;
    v_customization jsonb;
    v_modes jsonb;
    v_value text;
    v_key text;
begin
    select * into v_ctx from public.get_current_actor_context();

    if not coalesce(v_ctx.is_admin, false) then
        raise exception 'Acesso negado: somente administradores podem alterar o gerenciamento.';
    end if;
    if p_config is null or jsonb_typeof(p_config) <> 'object' then
        raise exception 'Configuracao invalida.';
    end if;

    v_customization := coalesce(p_config -> 'customization', '{}'::jsonb);
    if jsonb_typeof(v_customization) <> 'object' then
        raise exception 'Configuracao dos seletores invalida.';
    end if;

    foreach v_key in array array['workflow', 'modules', 'ticket_fields', 'overview']
    loop
        if v_customization -> v_key is not null
           and jsonb_typeof(v_customization -> v_key) <> 'boolean' then
            raise exception 'O seletor % deve ser verdadeiro ou falso.', v_key;
        end if;
    end loop;

    v_customization := jsonb_build_object(
        'workflow', lower(coalesce(v_customization ->> 'workflow', 'false')) = 'true',
        'modules', lower(coalesce(v_customization ->> 'modules', 'false')) = 'true',
        'ticket_fields', lower(coalesce(v_customization ->> 'ticket_fields', 'false')) = 'true',
        'overview', lower(coalesce(v_customization ->> 'overview', 'false')) = 'true'
    );
    v_config := jsonb_set(p_config, '{customization}', v_customization, true);

    if not (v_customization ->> 'workflow')::boolean then
        v_config := jsonb_set(
            v_config,
            '{workflow}',
            coalesce(v_config -> 'workflow', '{}'::jsonb) || jsonb_build_object(
                'parts_control', true,
                'analysis_timer', true,
                'repair_timer', true,
                'delivery_mode', 'complete',
                'priority_requests', true
            ),
            true
        );
    end if;

    if jsonb_typeof(coalesce(v_config -> 'modules', '{}'::jsonb)) <> 'object' then
        raise exception 'Configuracao de modulos invalida.';
    end if;

    if not (v_customization ->> 'modules')::boolean then
        v_config := jsonb_set(
            v_config,
            '{modules}',
            coalesce(v_config -> 'modules', '{}'::jsonb) || jsonb_build_object(
                'agenda', true,
                'suppliers', true,
                'manager_dashboard', true,
                'public_tracker', true,
                'customers', true
            ),
            true
        );
    else
        v_config := jsonb_set(
            v_config,
            '{modules}',
            coalesce(v_config -> 'modules', '{}'::jsonb) || jsonb_build_object(
                'customers',
                public.aida_config_bool(v_config, 'modules', 'customers', true)
            ),
            true
        );
    end if;

    if not (v_customization ->> 'ticket_fields')::boolean then
        v_config := jsonb_set(v_config, '{ticket_field_modes}', jsonb_build_object(
            'client_name', 'required',
            'contact_info', 'optional',
            'os_number', 'required',
            'serial_number', 'optional',
            'priority', 'optional',
            'device_model', 'required',
            'analysis_deadline', 'required',
            'deadline', 'required',
            'device_condition', 'optional',
            'responsible', 'required',
            'defect_reported', 'required',
            'checklist_entry', 'optional',
            'checklist_exit', 'optional',
            'photos', 'optional',
            'analysis_schedule', 'optional',
            'repair_schedule', 'optional'
        ), true);
    end if;

    if not (v_customization ->> 'overview')::boolean then
        v_config := jsonb_set(v_config, '{overview_sections}', jsonb_build_object(
            'awaiting_start', true,
            'awaiting_budget', true,
            'parts_purchase', true,
            'parts_receipt', true,
            'tests', true,
            'pickup', true,
            'overdue', true,
            'unscheduled', true,
            'priority', true
        ), true);
    end if;

    if jsonb_typeof(coalesce(v_config -> 'workflow', '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(v_config -> 'overview_sections', '{}'::jsonb)) <> 'object' then
        raise exception 'Configuracao de gerenciamento invalida.';
    end if;

    v_modes := coalesce(v_config -> 'ticket_field_modes', '{}'::jsonb);
    if jsonb_typeof(v_modes) <> 'object' then
        raise exception 'Configuracao de campos invalida.';
    end if;

    for v_value in select value #>> '{}' from jsonb_each(v_modes)
    loop
        if v_value not in ('disabled', 'optional', 'required') then
            raise exception 'Modo de campo invalido: %.', v_value;
        end if;
    end loop;

    if coalesce(v_config -> 'workflow' ->> 'delivery_mode', 'complete') not in ('complete', 'simple') then
        raise exception 'Modo de retirada/entrega invalido.';
    end if;

    if not public.aida_config_bool(v_config, 'workflow', 'parts_control', true)
       and exists (
            select 1
              from public.tickets t
             where t.workspace_id = v_ctx.workspace_id
               and t.deleted_at is null
               and (
                    t.status = 'Compra Peca'
                    or t.repair_paused_at is not null
                    or (t.parts_status in ('Pendente', 'Comprado') and t.status <> 'Finalizado')
               )
       ) then
        raise exception 'Nao e possivel desativar Compra de Pecas: existem OS em compra ou reparos pausados. Conclua essas OS primeiro.';
    end if;

    v_config := jsonb_set(
        v_config,
        '{ticket_field_modes}',
        v_modes || jsonb_build_object(
            'client_name', 'required',
            'os_number', 'required',
            'device_model', 'required'
        ),
        true
    );

    update public.workspaces
       set tracker_config = v_config
     where id = v_ctx.workspace_id;

    if not found then
        raise exception 'Workspace nao encontrado.';
    end if;
end;
$$;

revoke all on table public.customers from public, anon, authenticated;
grant select, insert, update on table public.customers to anon, authenticated;

revoke all on function public.aida_enforce_customer_identity() from public;
revoke all on function public.aida_enforce_ticket_customer_link() from public;
revoke all on function public.aida_customers_enabled() from public;
revoke all on function public.get_customer_page(text, integer, jsonb, boolean) from public;
revoke all on function public.get_customer_ticket_page(uuid, text, integer, jsonb, boolean) from public;
revoke all on function public.save_customer(jsonb) from public;
revoke all on function public.update_workspace_tracker_config(jsonb) from public;

grant execute on function public.get_customer_page(text, integer, jsonb, boolean) to anon, authenticated;
grant execute on function public.get_customer_ticket_page(uuid, text, integer, jsonb, boolean) to anon, authenticated;
grant execute on function public.save_customer(jsonb) to anon, authenticated;
grant execute on function public.aida_customers_enabled() to anon, authenticated;
grant execute on function public.update_workspace_tracker_config(jsonb) to anon, authenticated;

comment on table public.customers is
    'Cadastro opcional de clientes por empresa. Exclusao e logica por deleted_at.';
comment on column public.tickets.customer_id is
    'Vinculo opcional com customers; client_name/contact_info permanecem como snapshot da OS.';
comment on function public.get_customer_page(text, integer, jsonb, boolean) is
    'Lista clientes ativos com keyset. A empresa vem apenas do ator atual.';
comment on function public.get_customer_ticket_page(uuid, text, integer, jsonb, boolean) is
    'Lista cards leves das OS de um cliente com keyset e RLS das OS.';
comment on function public.save_customer(jsonb) is
    'Cria, atualiza ou exclui logicamente um cliente da empresa do ator atual.';

notify pgrst, 'reload schema';

commit;
