-- Modulo opcional de estoque da AIDA-GEST.
-- Esta migration cria a estrutura e as APIs do catalogo/saldo.
-- O recurso permanece DESLIGADO por padrao e nao altera OS legadas.

begin;

create schema if not exists private;

create table if not exists public.inventory_items (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete restrict,
    name text not null,
    sku text,
    universal_code text,
    category text,
    brand text,
    description text,
    internal_notes text,
    image_url text,
    last_purchase_at timestamptz,
    unit_code text not null default 'un',
    custom_unit_name text,
    allow_decimal boolean not null default false,
    track_stock boolean not null default true,
    minimum_quantity numeric(14,3) not null default 0,
    ideal_quantity numeric(14,3) not null default 0,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_items_name_nonblank check (btrim(name) <> ''),
    constraint inventory_items_unit_check check (
        unit_code in ('un', 'pc', 'kit', 'm', 'cm', 'mm', 'g', 'kg', 'ml', 'l', 'roll', 'box', 'custom')
    ),
    constraint inventory_items_custom_unit_check check (
        unit_code <> 'custom' or nullif(btrim(custom_unit_name), '') is not null
    ),
    constraint inventory_items_thresholds_check check (
        minimum_quantity >= 0 and ideal_quantity >= 0
    ),
    constraint inventory_items_integer_unit_check check (
        allow_decimal
        or (
            minimum_quantity = trunc(minimum_quantity)
            and ideal_quantity = trunc(ideal_quantity)
        )
    ),
    unique (workspace_id, id)
);

create unique index if not exists inventory_items_workspace_sku_uq
    on public.inventory_items(workspace_id, lower(btrim(sku)))
    where sku is not null and btrim(sku) <> '';
create index if not exists inventory_items_workspace_name_idx
    on public.inventory_items(workspace_id, lower(name), id)
    where active;
create index if not exists inventory_items_workspace_category_idx
    on public.inventory_items(workspace_id, category, lower(name), id)
    where active;

create table if not exists public.inventory_item_costs (
    item_id uuid primary key,
    workspace_id uuid not null,
    average_cost numeric(14,4) not null default 0,
    last_cost numeric(14,4) not null default 0,
    updated_at timestamptz not null default now(),
    constraint inventory_item_costs_item_fkey
        foreign key (workspace_id, item_id)
        references public.inventory_items(workspace_id, id)
        on delete cascade,
    constraint inventory_item_costs_nonnegative check (
        average_cost >= 0 and last_cost >= 0
    ),
    unique (workspace_id, item_id)
);

create table if not exists public.inventory_location_schemes (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete restrict,
    name text not null,
    mode text not null default 'free',
    component_labels jsonb not null default '[]'::jsonb,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_location_schemes_name_nonblank check (btrim(name) <> ''),
    constraint inventory_location_schemes_mode_check check (mode in ('free', 'structured')),
    constraint inventory_location_schemes_components_check check (
        jsonb_typeof(component_labels) = 'array'
        and jsonb_array_length(component_labels) <= 8
    ),
    unique (workspace_id, id)
);

create table if not exists public.inventory_locations (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete restrict,
    scheme_id uuid,
    name text not null,
    address_components jsonb not null default '{}'::jsonb,
    normalized_address text not null,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_locations_scheme_fkey
        foreign key (workspace_id, scheme_id)
        references public.inventory_location_schemes(workspace_id, id)
        on delete restrict,
    constraint inventory_locations_name_nonblank check (btrim(name) <> ''),
    constraint inventory_locations_address_nonblank check (btrim(normalized_address) <> ''),
    constraint inventory_locations_components_check check (
        jsonb_typeof(address_components) = 'object'
    ),
    unique (workspace_id, id)
);

create unique index if not exists inventory_locations_workspace_address_uq
    on public.inventory_locations(workspace_id, lower(normalized_address))
    where active;
create index if not exists inventory_locations_workspace_name_idx
    on public.inventory_locations(workspace_id, lower(name), id)
    where active;

alter table public.inventory_items
    add column if not exists default_location_id uuid;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'inventory_items_default_location_fkey'
          and conrelid = 'public.inventory_items'::regclass
    ) then
        alter table public.inventory_items
            add constraint inventory_items_default_location_fkey
            foreign key (workspace_id, default_location_id)
            references public.inventory_locations(workspace_id, id)
            on delete restrict;
    end if;
end;
$$;

create table if not exists public.inventory_balances (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    item_id uuid not null,
    location_id uuid not null,
    physical_quantity numeric(14,3) not null default 0,
    reserved_quantity numeric(14,3) not null default 0,
    available_quantity numeric(14,3)
        generated always as (physical_quantity - reserved_quantity) stored,
    updated_at timestamptz not null default now(),
    constraint inventory_balances_item_fkey
        foreign key (workspace_id, item_id)
        references public.inventory_items(workspace_id, id)
        on delete restrict,
    constraint inventory_balances_location_fkey
        foreign key (workspace_id, location_id)
        references public.inventory_locations(workspace_id, id)
        on delete restrict,
    constraint inventory_balances_nonnegative check (
        physical_quantity >= 0
        and reserved_quantity >= 0
        and reserved_quantity <= physical_quantity
    ),
    unique (workspace_id, item_id, location_id),
    unique (workspace_id, id)
);

create index if not exists inventory_balances_workspace_item_idx
    on public.inventory_balances(workspace_id, item_id, location_id);
create index if not exists inventory_balances_low_stock_idx
    on public.inventory_balances(workspace_id, available_quantity, item_id);

create unique index if not exists device_models_workspace_id_id_uidx
    on public.device_models(workspace_id, id);

create table if not exists public.inventory_item_models (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    item_id uuid not null,
    device_model_id uuid not null,
    created_at timestamptz not null default now(),
    constraint inventory_item_models_item_fkey
        foreign key (workspace_id, item_id)
        references public.inventory_items(workspace_id, id)
        on delete cascade,
    constraint inventory_item_models_model_fkey
        foreign key (workspace_id, device_model_id)
        references public.device_models(workspace_id, id)
        on delete restrict,
    unique (workspace_id, item_id, device_model_id)
);

create index if not exists inventory_item_models_model_idx
    on public.inventory_item_models(workspace_id, device_model_id, item_id);

create unique index if not exists fornecedores_workspace_id_id_uidx
    on public.fornecedores(workspace_id, id);

create table if not exists public.inventory_item_suppliers (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    item_id uuid not null,
    supplier_id uuid not null,
    supplier_sku text,
    last_price numeric(14,4),
    lead_time_days integer,
    preferred boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_item_suppliers_item_fkey
        foreign key (workspace_id, item_id)
        references public.inventory_items(workspace_id, id)
        on delete cascade,
    constraint inventory_item_suppliers_supplier_fkey
        foreign key (workspace_id, supplier_id)
        references public.fornecedores(workspace_id, id)
        on delete restrict,
    constraint inventory_item_suppliers_values_check check (
        (last_price is null or last_price >= 0)
        and (lead_time_days is null or lead_time_days >= 0)
    ),
    unique (workspace_id, item_id, supplier_id)
);

create index if not exists inventory_item_suppliers_supplier_idx
    on public.inventory_item_suppliers(workspace_id, supplier_id, item_id);

create table if not exists public.inventory_item_relations (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    source_item_id uuid not null,
    target_item_id uuid not null,
    relation_type text not null,
    created_at timestamptz not null default now(),
    constraint inventory_item_relations_source_fkey
        foreign key (workspace_id, source_item_id)
        references public.inventory_items(workspace_id, id)
        on delete cascade,
    constraint inventory_item_relations_target_fkey
        foreign key (workspace_id, target_item_id)
        references public.inventory_items(workspace_id, id)
        on delete cascade,
    constraint inventory_item_relations_type_check check (
        relation_type in ('equivalent', 'substitute')
    ),
    constraint inventory_item_relations_distinct_check check (
        source_item_id <> target_item_id
    ),
    unique (workspace_id, source_item_id, target_item_id, relation_type)
);

create index if not exists inventory_item_relations_target_idx
    on public.inventory_item_relations(workspace_id, target_item_id, relation_type);

create table if not exists public.ticket_part_items (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    ticket_id uuid not null,
    requested_item_id uuid not null,
    original_item_id uuid,
    substitution_type text,
    requested_name_snapshot text not null,
    requested_quantity numeric(14,3) not null,
    request_stage text not null,
    status text not null default 'needed',
    notes text,
    requested_by_user_id uuid,
    requested_by_employee_id uuid,
    requested_by_name text not null,
    approved_at timestamptz,
    cancelled_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ticket_part_items_ticket_fkey
        foreign key (workspace_id, ticket_id)
        references public.tickets(workspace_id, id)
        on delete restrict,
    constraint ticket_part_items_item_fkey
        foreign key (workspace_id, requested_item_id)
        references public.inventory_items(workspace_id, id)
        on delete restrict,
    constraint ticket_part_items_original_item_fkey
        foreign key (workspace_id, original_item_id)
        references public.inventory_items(workspace_id, id)
        on delete restrict,
    constraint ticket_part_items_substitution_check check (
        (original_item_id is null and substitution_type is null)
        or (original_item_id is not null and substitution_type in ('equivalent', 'substitute'))
    ),
    constraint ticket_part_items_quantity_check check (requested_quantity > 0),
    constraint ticket_part_items_stage_check check (
        request_stage in ('analysis', 'direct_repair', 'repair', 'warranty')
    ),
    constraint ticket_part_items_status_check check (
        status in (
            'needed', 'pending_approval', 'reserved', 'partial',
            'purchase_pending', 'ready', 'consumed', 'released', 'cancelled'
        )
    ),
    unique (workspace_id, id)
);

create index if not exists ticket_part_items_ticket_idx
    on public.ticket_part_items(workspace_id, ticket_id, status, created_at);
create index if not exists ticket_part_items_item_idx
    on public.ticket_part_items(workspace_id, requested_item_id, status);

create table if not exists public.inventory_reservations (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    ticket_part_item_id uuid not null,
    item_id uuid not null,
    location_id uuid not null,
    reserved_quantity numeric(14,3) not null,
    consumed_quantity numeric(14,3) not null default 0,
    released_quantity numeric(14,3) not null default 0,
    returned_quantity numeric(14,3) not null default 0,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_reservations_part_fkey
        foreign key (workspace_id, ticket_part_item_id)
        references public.ticket_part_items(workspace_id, id)
        on delete restrict,
    constraint inventory_reservations_item_fkey
        foreign key (workspace_id, item_id)
        references public.inventory_items(workspace_id, id)
        on delete restrict,
    constraint inventory_reservations_location_fkey
        foreign key (workspace_id, location_id)
        references public.inventory_locations(workspace_id, id)
        on delete restrict,
    constraint inventory_reservations_quantities_check check (
        reserved_quantity > 0
        and consumed_quantity >= 0
        and released_quantity >= 0
        and returned_quantity >= 0
        and consumed_quantity + released_quantity <= reserved_quantity
        and returned_quantity <= consumed_quantity
    ),
    constraint inventory_reservations_status_check check (
        status in ('active', 'consumed', 'released', 'cancelled')
    ),
    unique (workspace_id, id)
);

create index if not exists inventory_reservations_part_idx
    on public.inventory_reservations(workspace_id, ticket_part_item_id, status);
create index if not exists inventory_reservations_item_location_idx
    on public.inventory_reservations(workspace_id, item_id, location_id, status);

create table if not exists public.inventory_purchases (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete restrict,
    supplier_id uuid not null,
    supplier_name_snapshot text not null,
    status text not null default 'draft',
    urgent boolean not null default false,
    notes text,
    discount_amount numeric(14,2) not null default 0,
    surcharge_amount numeric(14,2) not null default 0,
    ordered_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    created_by_user_id uuid,
    created_by_employee_id uuid,
    created_by_name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_purchases_status_check check (
        status in ('draft', 'ordered', 'partial', 'received', 'cancelled')
    ),
    constraint inventory_purchases_supplier_fkey
        foreign key (workspace_id, supplier_id)
        references public.fornecedores(workspace_id, id)
        on delete restrict,
    unique (workspace_id, id)
);

create index if not exists inventory_purchases_queue_idx
    on public.inventory_purchases(workspace_id, status, urgent desc, created_at, id);
create index if not exists inventory_purchases_supplier_idx
    on public.inventory_purchases(workspace_id, supplier_id, created_at desc);

create table if not exists public.inventory_purchase_items (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    purchase_id uuid not null,
    item_id uuid not null,
    item_name_snapshot text not null,
    ordered_quantity numeric(14,3) not null,
    received_quantity numeric(14,3) not null default 0,
    unit_cost numeric(14,4),
    supplier_sku_snapshot text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_purchase_items_purchase_fkey
        foreign key (workspace_id, purchase_id)
        references public.inventory_purchases(workspace_id, id)
        on delete restrict,
    constraint inventory_purchase_items_item_fkey
        foreign key (workspace_id, item_id)
        references public.inventory_items(workspace_id, id)
        on delete restrict,
    constraint inventory_purchase_items_quantities_check check (
        ordered_quantity > 0
        and received_quantity >= 0
        and received_quantity <= ordered_quantity
        and (unit_cost is null or unit_cost >= 0)
    ),
    unique (workspace_id, id)
);

create index if not exists inventory_purchase_items_purchase_idx
    on public.inventory_purchase_items(workspace_id, purchase_id, id);

create table if not exists public.inventory_purchase_allocations (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    purchase_item_id uuid not null,
    ticket_part_item_id uuid not null,
    allocated_quantity numeric(14,3) not null,
    fulfilled_quantity numeric(14,3) not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inventory_purchase_allocations_purchase_item_fkey
        foreign key (workspace_id, purchase_item_id)
        references public.inventory_purchase_items(workspace_id, id)
        on delete restrict,
    constraint inventory_purchase_allocations_part_fkey
        foreign key (workspace_id, ticket_part_item_id)
        references public.ticket_part_items(workspace_id, id)
        on delete restrict,
    constraint inventory_purchase_allocations_quantities_check check (
        allocated_quantity > 0
        and fulfilled_quantity >= 0
        and fulfilled_quantity <= allocated_quantity
    ),
    unique (workspace_id, purchase_item_id, ticket_part_item_id)
);

create index if not exists inventory_purchase_allocations_part_idx
    on public.inventory_purchase_allocations(workspace_id, ticket_part_item_id);

create table if not exists public.inventory_movements (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null,
    item_id uuid not null,
    location_id uuid not null,
    movement_type text not null,
    physical_delta numeric(14,3) not null default 0,
    reserved_delta numeric(14,3) not null default 0,
    physical_before numeric(14,3),
    physical_after numeric(14,3),
    reserved_before numeric(14,3),
    reserved_after numeric(14,3),
    counterpart_location_id uuid,
    unit_cost_snapshot numeric(14,4),
    ticket_id uuid,
    ticket_part_item_id uuid,
    purchase_id uuid,
    transfer_group_id uuid,
    reason text,
    actor_user_id uuid,
    actor_employee_id uuid,
    actor_name text not null,
    created_at timestamptz not null default now(),
    constraint inventory_movements_item_fkey
        foreign key (workspace_id, item_id)
        references public.inventory_items(workspace_id, id)
        on delete restrict,
    constraint inventory_movements_location_fkey
        foreign key (workspace_id, location_id)
        references public.inventory_locations(workspace_id, id)
        on delete restrict,
    constraint inventory_movements_counterpart_location_fkey
        foreign key (workspace_id, counterpart_location_id)
        references public.inventory_locations(workspace_id, id)
        on delete restrict,
    constraint inventory_movements_ticket_fkey
        foreign key (workspace_id, ticket_id)
        references public.tickets(workspace_id, id)
        on delete restrict,
    constraint inventory_movements_part_fkey
        foreign key (workspace_id, ticket_part_item_id)
        references public.ticket_part_items(workspace_id, id)
        on delete restrict,
    constraint inventory_movements_purchase_fkey
        foreign key (workspace_id, purchase_id)
        references public.inventory_purchases(workspace_id, id)
        on delete restrict,
    constraint inventory_movements_type_check check (
        movement_type in (
            'opening', 'manual_entry', 'purchase_receipt', 'reserve', 'release',
            'consume', 'return', 'adjustment', 'transfer_out', 'transfer_in'
        )
    ),
    constraint inventory_movements_delta_check check (
        physical_delta <> 0 or reserved_delta <> 0
    ),
    constraint inventory_movements_cost_check check (
        unit_cost_snapshot is null or unit_cost_snapshot >= 0
    )
);

create index if not exists inventory_movements_item_created_idx
    on public.inventory_movements(workspace_id, item_id, created_at desc, id desc);
create index if not exists inventory_movements_ticket_created_idx
    on public.inventory_movements(workspace_id, ticket_id, created_at desc)
    where ticket_id is not null;
create index if not exists inventory_movements_purchase_created_idx
    on public.inventory_movements(workspace_id, purchase_id, created_at desc)
    where purchase_id is not null;

-- RLS em todas as tabelas. As APIs publicas derivam o workspace pelo ator atual.
alter table public.inventory_items enable row level security;
alter table public.inventory_item_costs enable row level security;
alter table public.inventory_location_schemes enable row level security;
alter table public.inventory_locations enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.inventory_item_models enable row level security;
alter table public.inventory_item_suppliers enable row level security;
alter table public.inventory_item_relations enable row level security;
alter table public.ticket_part_items enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.inventory_purchases enable row level security;
alter table public.inventory_purchase_items enable row level security;
alter table public.inventory_purchase_allocations enable row level security;
alter table public.inventory_movements enable row level security;

-- Nenhuma gravacao direta e permitida pela Data API.
revoke all on table
    public.inventory_items,
    public.inventory_item_costs,
    public.inventory_location_schemes,
    public.inventory_locations,
    public.inventory_balances,
    public.inventory_item_models,
    public.inventory_item_suppliers,
    public.inventory_item_relations,
    public.ticket_part_items,
    public.inventory_reservations,
    public.inventory_purchases,
    public.inventory_purchase_items,
    public.inventory_purchase_allocations,
    public.inventory_movements
from public, anon, authenticated;

create or replace function private.inventory_config_enabled(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        public.aida_config_bool(coalesce(w.tracker_config, '{}'::jsonb), 'workflow', 'parts_control', true)
        and public.aida_config_bool(coalesce(w.tracker_config, '{}'::jsonb), 'modules', 'inventory', false)
    from public.workspaces w
    where w.id = p_workspace_id;
$$;

revoke all on function private.inventory_config_enabled(uuid) from public, anon, authenticated;

create or replace function private.inventory_assert_access(
    p_workspace_id uuid,
    p_required text default 'read'
)
returns table (
    actor_user_id uuid,
    actor_employee_id uuid,
    actor_name text,
    actor_roles text[],
    is_admin boolean,
    is_attendant boolean,
    is_technician boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
begin
    select * into v_ctx from public.get_current_actor_context();

    if v_ctx.workspace_id is distinct from p_workspace_id then
        raise exception 'Acesso negado ao estoque de outra empresa.';
    end if;
    if not coalesce(private.inventory_config_enabled(p_workspace_id), false) then
        raise exception 'O modulo de estoque esta desativado.';
    end if;
    if p_required = 'admin' and not v_ctx.is_admin then
        raise exception 'Somente administradores podem realizar esta acao no estoque.';
    end if;
    if p_required = 'manage' and not (v_ctx.is_admin or v_ctx.is_attendant) then
        raise exception 'Apenas administradores e atendentes podem gerenciar o estoque.';
    end if;
    if p_required = 'read' and not (
        v_ctx.is_admin or v_ctx.is_attendant or v_ctx.is_technician
    ) then
        raise exception 'Este cargo nao possui acesso ao estoque.';
    end if;

    return query select
        v_ctx.actor_user_id,
        v_ctx.actor_employee_id,
        v_ctx.actor_name,
        v_ctx.actor_roles,
        v_ctx.is_admin,
        v_ctx.is_attendant,
        v_ctx.is_technician;
end;
$$;

revoke all on function private.inventory_assert_access(uuid, text)
from public, anon, authenticated;

create or replace function private.inventory_movements_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    raise exception 'Movimentacoes de estoque sao imutaveis. Registre um novo ajuste.';
end;
$$;

revoke all on function private.inventory_movements_immutable()
from public, anon, authenticated;

drop trigger if exists inventory_movements_block_mutation on public.inventory_movements;
create trigger inventory_movements_block_mutation
before update or delete on public.inventory_movements
for each row execute function private.inventory_movements_immutable();

create or replace function public.get_inventory_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    select jsonb_build_object(
        'active_items', count(*) filter (where i.active),
        'tracked_items', count(*) filter (where i.active and i.track_stock),
        'low_stock_items', count(*) filter (
            where i.active and i.track_stock
              and coalesce(b.available, 0) <= i.minimum_quantity
        ),
        'out_of_stock_items', count(*) filter (
            where i.active and i.track_stock and coalesce(b.available, 0) <= 0
        ),
        'estimated_stock_value', (
            select coalesce(sum(b.physical_quantity * c.average_cost), 0)
            from public.inventory_balances b
            join public.inventory_item_costs c
              on c.workspace_id = b.workspace_id and c.item_id = b.item_id
            where b.workspace_id = v_ctx.workspace_id
        ),
        'open_purchases', (
            select count(*)
            from public.inventory_purchases p
            where p.workspace_id = v_ctx.workspace_id
              and p.status in ('draft', 'ordered', 'partial')
        ),
        'pending_ticket_parts', (
            select count(*)
            from public.ticket_part_items tp
            where tp.workspace_id = v_ctx.workspace_id
              and tp.status in ('partial', 'purchase_pending')
        )
    )
    into v_result
    from public.inventory_items i
    left join lateral (
        select sum(ib.available_quantity) available
        from public.inventory_balances ib
        where ib.workspace_id = i.workspace_id and ib.item_id = i.id
    ) b on true
    where i.workspace_id = v_ctx.workspace_id;

    return coalesce(v_result, '{}'::jsonb);
end;
$$;

revoke all on function public.get_inventory_dashboard() from public;
grant execute on function public.get_inventory_dashboard() to anon, authenticated;

create or replace function public.get_inventory_items_page(
    p_search text default null,
    p_category text default null,
    p_stock_filter text default 'all',
    p_limit integer default 25,
    p_cursor jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
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
    perform private.inventory_assert_access(v_ctx.workspace_id, 'manage');

    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;
    if p_stock_filter not in ('all', 'low', 'out', 'available', 'catalog', 'pending', 'inactive') then
        raise exception 'Filtro de estoque invalido.';
    end if;
    if p_cursor is not null then
        begin
            v_cursor_name := p_cursor ->> 'name';
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de estoque invalido.';
        end;
    end if;

    with base as materialized (
        select
            i.id,
            i.name,
            i.sku,
            i.universal_code,
            i.category,
            i.brand,
            i.unit_code,
            i.custom_unit_name,
            i.allow_decimal,
            i.track_stock,
            i.minimum_quantity,
            i.ideal_quantity,
            i.default_location_id,
            i.active,
            (
                select concat_ws(' · ', l.name, nullif(l.normalized_address, l.name))
                from public.inventory_balances ib
                join public.inventory_locations l
                  on l.workspace_id = ib.workspace_id and l.id = ib.location_id
                where ib.workspace_id = i.workspace_id
                  and ib.item_id = i.id
                  and ib.physical_quantity > 0
                order by
                    case when l.id = i.default_location_id then 0 else 1 end,
                    l.normalized_address,
                    l.id
                limit 1
            ) primary_location,
            coalesce(b.physical, 0) physical_quantity,
            coalesce(b.reserved, 0) reserved_quantity,
            coalesce(b.available, 0) available_quantity,
            c.average_cost,
            c.last_cost,
            lower(i.name) sort_name
        from public.inventory_items i
        left join public.inventory_item_costs c
          on c.workspace_id = i.workspace_id and c.item_id = i.id
        left join lateral (
            select
                sum(ib.physical_quantity) physical,
                sum(ib.reserved_quantity) reserved,
                sum(ib.available_quantity) available
            from public.inventory_balances ib
            where ib.workspace_id = i.workspace_id and ib.item_id = i.id
        ) b on true
        where i.workspace_id = v_ctx.workspace_id
          and (case when p_stock_filter = 'inactive' then not i.active else i.active end)
          and (
              v_search is null
              or i.name ilike '%' || v_search || '%'
              or coalesce(i.sku, '') ilike '%' || v_search || '%'
              or coalesce(i.universal_code, '') ilike '%' || v_search || '%'
              or coalesce(i.brand, '') ilike '%' || v_search || '%'
              or exists (
                  select 1 from public.inventory_balances ib
                  join public.inventory_locations il
                    on il.workspace_id = ib.workspace_id and il.id = ib.location_id
                  where ib.workspace_id = i.workspace_id and ib.item_id = i.id
                    and (il.name ilike '%' || v_search || '%'
                         or il.normalized_address ilike '%' || v_search || '%')
              )
          )
          and (p_category is null or p_category = '' or lower(coalesce(i.category, '')) = lower(p_category))
    ), filtered as (
        select *
        from base b
        where (
            p_stock_filter = 'all'
            or (p_stock_filter = 'low' and b.track_stock and b.available_quantity <= b.minimum_quantity)
            or (p_stock_filter = 'out' and b.track_stock and b.available_quantity <= 0)
            or (p_stock_filter = 'available' and b.track_stock and b.available_quantity > 0)
            or (p_stock_filter = 'catalog' and not b.track_stock)
            or (p_stock_filter = 'inactive' and not b.active)
            or (p_stock_filter = 'pending' and exists (
                select 1 from public.ticket_part_items tp
                where tp.workspace_id = v_ctx.workspace_id
                  and tp.requested_item_id = b.id
                  and tp.status in ('partial', 'purchase_pending')
            ))
        )
        and (
            p_cursor is null
            or (b.sort_name, b.id) > (v_cursor_name, v_cursor_id)
        )
    ), page_plus_one as materialized (
        select * from filtered order by sort_name, id limit p_limit + 1
    ), page_rows as materialized (
        select * from page_plus_one order by sort_name, id limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(to_jsonb(p) - 'sort_name' order by p.sort_name, p.id)
            from page_rows p
        ), '[]'::jsonb),
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (
            select jsonb_build_object('name', p.sort_name, 'id', p.id)
            from page_rows p order by p.sort_name desc, p.id desc limit 1
        )
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_inventory_items_page(text, text, text, integer, jsonb) from public;
grant execute on function public.get_inventory_items_page(text, text, text, integer, jsonb)
to anon, authenticated;

create or replace function public.get_inventory_catalog_page(
    p_ticket_id uuid,
    p_search text default null,
    p_limit integer default 20,
    p_cursor jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_search text := nullif(btrim(coalesce(p_search, '')), '');
    v_cursor_name text;
    v_cursor_id uuid;
    v_cursor_compatible boolean;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'read');

    select * into v_ticket
    from public.tickets t
    where t.id = p_ticket_id
      and t.workspace_id = v_ctx.workspace_id
      and t.deleted_at is null;

    if not found then raise exception 'OS nao encontrada.'; end if;
    if v_ctx.is_technician
       and not v_ctx.is_admin
       and not v_ctx.is_attendant
       and v_ticket.technician_id is distinct from v_ctx.actor_employee_id then
        raise exception 'Tecnico so pode consultar estoque para a propria OS.';
    end if;
    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;
    if length(coalesce(v_search, '')) > 120 then
        raise exception 'A busca deve ter no maximo 120 caracteres.';
    end if;
    if p_cursor is not null then
        begin
            v_cursor_name := p_cursor ->> 'name';
            v_cursor_id := (p_cursor ->> 'id')::uuid;
            v_cursor_compatible := (p_cursor ->> 'compatible')::boolean;
        exception when others then
            raise exception 'Cursor de catalogo invalido.';
        end;
    end if;

    with base as materialized (
        select
            i.id,
            i.name,
            i.sku,
            i.category,
            i.brand,
            i.unit_code,
            i.custom_unit_name,
            i.allow_decimal,
            i.track_stock,
            coalesce(b.physical, 0) physical_quantity,
            coalesce(b.reserved, 0) reserved_quantity,
            coalesce(b.available, 0) available_quantity,
            (
                select l.name
                from public.inventory_balances ib
                join public.inventory_locations l
                  on l.workspace_id = ib.workspace_id and l.id = ib.location_id
                where ib.workspace_id = i.workspace_id
                  and ib.item_id = i.id
                  and ib.available_quantity > 0
                order by
                    case when l.id = i.default_location_id then 0 else 1 end,
                    l.normalized_address,
                    l.id
                limit 1
            ) primary_location,
            coalesce((
                select jsonb_agg(jsonb_build_object(
                    'id', alt.id,
                    'name', alt.name,
                    'sku', alt.sku,
                    'unit_code', alt.unit_code,
                    'allow_decimal', alt.allow_decimal,
                    'track_stock', alt.track_stock,
                    'relation_type', rel.relation_type,
                    'original_item_id', i.id,
                    'requested_original_name', i.name,
                    'available_quantity', coalesce(ab.available, 0),
                    'primary_location', ab.location_name
                ) order by rel.relation_type, lower(alt.name), alt.id)
                from public.inventory_item_relations rel
                join public.inventory_items alt
                  on alt.workspace_id = rel.workspace_id and alt.id = rel.target_item_id
                left join lateral (
                    select sum(ib.available_quantity) available,
                           min(l.name) filter (where ib.available_quantity > 0) location_name
                    from public.inventory_balances ib
                    join public.inventory_locations l
                      on l.workspace_id = ib.workspace_id and l.id = ib.location_id
                    where ib.workspace_id = alt.workspace_id and ib.item_id = alt.id
                ) ab on true
                where rel.workspace_id = i.workspace_id
                  and rel.source_item_id = i.id
                  and alt.active
            ), '[]'::jsonb) alternatives,
            exists (
                select 1
                from public.inventory_item_models im
                join public.device_models dm
                  on dm.workspace_id = im.workspace_id and dm.id = im.device_model_id
                where im.workspace_id = i.workspace_id
                  and im.item_id = i.id
                  and lower(dm.name) = lower(v_ticket.device_model)
            ) compatible_with_ticket,
            lower(i.name) sort_name
        from public.inventory_items i
        left join lateral (
            select
                sum(ib.physical_quantity) physical,
                sum(ib.reserved_quantity) reserved,
                sum(ib.available_quantity) available
            from public.inventory_balances ib
            where ib.workspace_id = i.workspace_id and ib.item_id = i.id
        ) b on true
        where i.workspace_id = v_ctx.workspace_id
          and i.active
          and (
              v_search is null
              or i.name ilike '%' || v_search || '%'
              or coalesce(i.sku, '') ilike '%' || v_search || '%'
              or coalesce(i.brand, '') ilike '%' || v_search || '%'
          )
    ), page_plus_one as materialized (
        select * from base b
        where p_cursor is null
           or (
                (case when b.compatible_with_ticket then 0 else 1 end, b.sort_name, b.id)
                >
                (case when v_cursor_compatible then 0 else 1 end, v_cursor_name, v_cursor_id)
           )
        order by compatible_with_ticket desc, sort_name, id
        limit p_limit + 1
    ), page_rows as materialized (
        select * from page_plus_one
        order by compatible_with_ticket desc, sort_name, id
        limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(to_jsonb(p) - 'sort_name'
                order by p.compatible_with_ticket desc, p.sort_name, p.id)
            from page_rows p
        ), '[]'::jsonb),
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', (
            select jsonb_build_object(
                'compatible', p.compatible_with_ticket,
                'name', p.sort_name,
                'id', p.id
            )
            from page_rows p
            order by p.compatible_with_ticket asc, p.sort_name desc, p.id desc
            limit 1
        )
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_inventory_catalog_page(uuid, text, integer, jsonb) from public;
grant execute on function public.get_inventory_catalog_page(uuid, text, integer, jsonb)
to anon, authenticated;

create or replace function public.save_inventory_item(p_item jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_id uuid;
    v_unit text;
    v_allow_decimal boolean;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');

    if p_item is null or jsonb_typeof(p_item) <> 'object' then
        raise exception 'Dados do item invalidos.';
    end if;
    if length(btrim(coalesce(p_item ->> 'name', ''))) < 2 then
        raise exception 'Informe um nome com pelo menos 2 caracteres.';
    end if;

    v_id := nullif(p_item ->> 'id', '')::uuid;
    v_unit := coalesce(nullif(p_item ->> 'unit_code', ''), 'un');
    v_allow_decimal := coalesce((p_item ->> 'allow_decimal')::boolean, false);

    if v_id is null then
        insert into public.inventory_items (
            workspace_id, name, sku, category, brand, description,
            unit_code, custom_unit_name, allow_decimal, track_stock,
            minimum_quantity, ideal_quantity, default_location_id
        ) values (
            v_ctx.workspace_id,
            btrim(p_item ->> 'name'),
            nullif(btrim(p_item ->> 'sku'), ''),
            nullif(btrim(p_item ->> 'category'), ''),
            nullif(btrim(p_item ->> 'brand'), ''),
            nullif(btrim(p_item ->> 'description'), ''),
            v_unit,
            nullif(btrim(p_item ->> 'custom_unit_name'), ''),
            v_allow_decimal,
            coalesce((p_item ->> 'track_stock')::boolean, true),
            coalesce((p_item ->> 'minimum_quantity')::numeric, 0),
            coalesce((p_item ->> 'ideal_quantity')::numeric, 0),
            nullif(p_item ->> 'default_location_id', '')::uuid
        )
        returning id into v_id;

        insert into public.inventory_item_costs(item_id, workspace_id)
        values (v_id, v_ctx.workspace_id);
    else
        update public.inventory_items i
        set name = btrim(p_item ->> 'name'),
            sku = nullif(btrim(p_item ->> 'sku'), ''),
            category = nullif(btrim(p_item ->> 'category'), ''),
            brand = nullif(btrim(p_item ->> 'brand'), ''),
            description = nullif(btrim(p_item ->> 'description'), ''),
            unit_code = v_unit,
            custom_unit_name = nullif(btrim(p_item ->> 'custom_unit_name'), ''),
            allow_decimal = v_allow_decimal,
            track_stock = coalesce((p_item ->> 'track_stock')::boolean, true),
            minimum_quantity = coalesce((p_item ->> 'minimum_quantity')::numeric, 0),
            ideal_quantity = coalesce((p_item ->> 'ideal_quantity')::numeric, 0),
            default_location_id = nullif(p_item ->> 'default_location_id', '')::uuid,
            updated_at = now()
        where i.id = v_id and i.workspace_id = v_ctx.workspace_id;
        if not found then raise exception 'Item nao encontrado.'; end if;
    end if;

    return v_id;
end;
$$;

revoke all on function public.save_inventory_item(jsonb) from public;
grant execute on function public.save_inventory_item(jsonb) to anon, authenticated;

create or replace function public.save_inventory_location(p_location jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_id uuid;
    v_name text;
    v_normalized text;
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');

    if p_location is null or jsonb_typeof(p_location) <> 'object' then
        raise exception 'Dados da localizacao invalidos.';
    end if;
    v_name := btrim(coalesce(p_location ->> 'name', ''));
    v_normalized := lower(regexp_replace(
        btrim(coalesce(p_location ->> 'normalized_address', v_name)),
        '\s+', ' ', 'g'
    ));
    if length(v_name) < 2 or length(v_normalized) < 2 then
        raise exception 'Informe um nome e um endereco validos.';
    end if;
    v_id := nullif(p_location ->> 'id', '')::uuid;

    if v_id is null then
        insert into public.inventory_locations(
            workspace_id, scheme_id, name, address_components, normalized_address
        ) values (
            v_ctx.workspace_id,
            nullif(p_location ->> 'scheme_id', '')::uuid,
            v_name,
            coalesce(p_location -> 'address_components', '{}'::jsonb),
            v_normalized
        ) returning id into v_id;
    else
        update public.inventory_locations l
        set scheme_id = nullif(p_location ->> 'scheme_id', '')::uuid,
            name = v_name,
            address_components = coalesce(p_location -> 'address_components', '{}'::jsonb),
            normalized_address = v_normalized,
            updated_at = now()
        where l.id = v_id and l.workspace_id = v_ctx.workspace_id;
        if not found then raise exception 'Localizacao nao encontrada.'; end if;
    end if;

    return v_id;
end;
$$;

revoke all on function public.save_inventory_location(jsonb) from public;
grant execute on function public.save_inventory_location(jsonb) to anon, authenticated;

create or replace function public.adjust_inventory_stock(
    p_item_id uuid,
    p_location_id uuid,
    p_new_physical_quantity numeric,
    p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_balance public.inventory_balances%rowtype;
    v_item public.inventory_items%rowtype;
    v_delta numeric(14,3);
begin
    select * into v_ctx from public.get_current_actor_context();
    perform private.inventory_assert_access(v_ctx.workspace_id, 'admin');

    if p_new_physical_quantity is null or p_new_physical_quantity < 0 then
        raise exception 'O saldo fisico nao pode ser negativo.';
    end if;
    if length(btrim(coalesce(p_reason, ''))) < 5 then
        raise exception 'Informe o motivo do ajuste.';
    end if;

    select * into v_item
    from public.inventory_items i
    where i.id = p_item_id and i.workspace_id = v_ctx.workspace_id and i.active
    for update;
    if not found or not v_item.track_stock then
        raise exception 'Item controlado nao encontrado.';
    end if;
    if not v_item.allow_decimal and p_new_physical_quantity <> trunc(p_new_physical_quantity) then
        raise exception 'Este item aceita apenas quantidades inteiras.';
    end if;

    if not exists (
        select 1 from public.inventory_locations l
        where l.id = p_location_id and l.workspace_id = v_ctx.workspace_id and l.active
    ) then
        raise exception 'Localizacao nao encontrada.';
    end if;

    insert into public.inventory_balances(
        workspace_id, item_id, location_id, physical_quantity, reserved_quantity
    ) values (
        v_ctx.workspace_id, p_item_id, p_location_id, 0, 0
    )
    on conflict (workspace_id, item_id, location_id) do nothing;

    select * into v_balance
    from public.inventory_balances b
    where b.workspace_id = v_ctx.workspace_id
      and b.item_id = p_item_id
      and b.location_id = p_location_id
    for update;

    if p_new_physical_quantity < v_balance.reserved_quantity then
        raise exception 'O saldo fisico nao pode ficar abaixo da quantidade reservada (%).',
            v_balance.reserved_quantity;
    end if;

    v_delta := p_new_physical_quantity - v_balance.physical_quantity;
    if v_delta = 0 then
        return jsonb_build_object(
            'success', true,
            'physical_quantity', v_balance.physical_quantity,
            'reserved_quantity', v_balance.reserved_quantity,
            'available_quantity', v_balance.available_quantity
        );
    end if;

    update public.inventory_balances
    set physical_quantity = p_new_physical_quantity, updated_at = now()
    where id = v_balance.id;

    insert into public.inventory_movements(
        workspace_id, item_id, location_id, movement_type,
        physical_delta, reserved_delta, reason,
        actor_user_id, actor_employee_id, actor_name
    ) values (
        v_ctx.workspace_id, p_item_id, p_location_id,
        case when v_balance.physical_quantity = 0 and v_delta > 0
             then 'opening' else 'adjustment' end,
        v_delta, 0, btrim(p_reason),
        v_ctx.actor_user_id, v_ctx.actor_employee_id, v_ctx.actor_name
    );

    return jsonb_build_object(
        'success', true,
        'physical_quantity', p_new_physical_quantity,
        'reserved_quantity', v_balance.reserved_quantity,
        'available_quantity', p_new_physical_quantity - v_balance.reserved_quantity
    );
end;
$$;

revoke all on function public.adjust_inventory_stock(uuid, uuid, numeric, text) from public;
grant execute on function public.adjust_inventory_stock(uuid, uuid, numeric, text)
to anon, authenticated;

-- O modulo e desligado por padrao, inclusive em configuracoes antigas.
-- A validacao de desativacao protege operacoes abertas sem apagar historico.
create or replace function private.validate_inventory_tracker_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_old_enabled boolean;
    v_new_enabled boolean;
    v_parts_enabled boolean;
begin
    if coalesce(new.tracker_config -> 'customization' ->> 'modules', 'false') <> 'true' then
        new.tracker_config := jsonb_set(
            coalesce(new.tracker_config, '{}'::jsonb),
            '{modules,inventory}',
            'false'::jsonb,
            true
        );
    end if;

    v_old_enabled := public.aida_config_bool(
        coalesce(old.tracker_config, '{}'::jsonb), 'modules', 'inventory', false
    );
    v_new_enabled := public.aida_config_bool(
        coalesce(new.tracker_config, '{}'::jsonb), 'modules', 'inventory', false
    );
    v_parts_enabled := public.aida_config_bool(
        coalesce(new.tracker_config, '{}'::jsonb), 'workflow', 'parts_control', true
    );

    if v_new_enabled and not v_parts_enabled then
        raise exception 'Ative o Controle de compra de pecas antes de ativar o Estoque.';
    end if;

    if v_old_enabled and not v_new_enabled and (
        exists (
            select 1 from public.inventory_reservations r
            where r.workspace_id = new.id and r.status = 'active'
              and r.reserved_quantity > r.consumed_quantity + r.released_quantity
        )
        or exists (
            select 1 from public.inventory_purchases p
            where p.workspace_id = new.id and p.status in ('draft', 'ordered', 'partial')
        )
        or exists (
            select 1 from public.ticket_part_items tp
            where tp.workspace_id = new.id
              and tp.status in ('needed', 'pending_approval', 'partial', 'purchase_pending', 'reserved', 'ready')
        )
    ) then
        raise exception 'Nao e possivel desativar o Estoque: existem reservas, solicitacoes ou compras abertas.';
    end if;

    return new;
end;
$$;

revoke all on function private.validate_inventory_tracker_config()
from public, anon, authenticated;

drop trigger if exists aida_validate_inventory_tracker_config on public.workspaces;
create trigger aida_validate_inventory_tracker_config
before update of tracker_config on public.workspaces
for each row execute function private.validate_inventory_tracker_config();

commit;
