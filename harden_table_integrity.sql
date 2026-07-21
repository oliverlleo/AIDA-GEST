-- Stage 6: strengthen relational and value integrity without rewriting legacy OS data.
--
-- Existing duplicate OS numbers and legacy workflow exceptions are preserved. New
-- or changed OS numbers are serialized and checked by a private trigger, while
-- foreign keys, tenant-consistency keys, JSON shapes and basic value constraints
-- prevent new invalid rows.

begin;

-- Preserve the only unusable orphan found by the audit before removing it. The
-- row points to a workspace that no longer exists and is invisible through RLS.
with orphan_rows as (
    select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb) as data
      from public.defect_options d
     where not exists (
        select 1 from public.workspaces w where w.id = d.workspace_id
     )
)
update private.security_stage_backups b
   set snapshot = b.snapshot || jsonb_build_object(
       'quarantined_rows',
       jsonb_build_object('defect_options', orphan_rows.data)
   )
  from orphan_rows
 where b.id = '655109f2-0f3d-48fb-8eb1-f901bcee8578'::uuid
   and b.label = 'pre_table_integrity_20260721';

delete from public.defect_options d
 where not exists (
    select 1 from public.workspaces w where w.id = d.workspace_id
 );

-- Case-insensitive uniqueness matches the validations already used by the UI.
create unique index if not exists employees_workspace_username_ci_uidx
    on public.employees (workspace_id, lower(btrim(username)));
create unique index if not exists workspaces_company_code_ci_uidx
    on public.workspaces (lower(btrim(company_code)));
create unique index if not exists defect_options_workspace_name_ci_uidx
    on public.defect_options (workspace_id, lower(btrim(name)));
create unique index if not exists defects_workspace_name_ci_uidx
    on public.defects (workspace_id, lower(btrim(name)));
create unique index if not exists device_models_workspace_name_ci_uidx
    on public.device_models (workspace_id, lower(btrim(name)));
create unique index if not exists checklist_templates_workspace_type_name_ci_uidx
    on public.checklist_templates (
        workspace_id,
        coalesce(type, 'entry'),
        lower(btrim(name))
    )
    where workspace_id is not null;

-- Parent keys used by composite foreign keys. They ensure a child cannot point
-- to a valid object from another workspace.
create unique index if not exists employees_workspace_id_id_uidx
    on public.employees (workspace_id, id);
create unique index if not exists tickets_workspace_id_id_uidx
    on public.tickets (workspace_id, id);
create unique index if not exists outsourced_companies_workspace_id_id_uidx
    on public.outsourced_companies (workspace_id, id);

-- Index every foreign-key access path used for parent deletes and joins.
create index if not exists checklist_templates_workspace_id_idx
    on public.checklist_templates (workspace_id);
create index if not exists fornecedores_workspace_id_idx
    on public.fornecedores (workspace_id);
create index if not exists internal_notes_ticket_id_idx
    on public.internal_notes (ticket_id);
create index if not exists internal_notes_workspace_id_idx
    on public.internal_notes (workspace_id);
create index if not exists notifications_ticket_id_idx
    on public.notifications (ticket_id);
create index if not exists outsourced_companies_workspace_id_idx
    on public.outsourced_companies (workspace_id);
create index if not exists profiles_workspace_id_idx
    on public.profiles (workspace_id);
create index if not exists suppliers_workspace_id_idx
    on public.suppliers (workspace_id);
create index if not exists technician_schedule_blocks_technician_id_idx
    on public.technician_schedule_blocks (technician_id);
create index if not exists terceirizados_workspace_id_idx
    on public.terceirizados (workspace_id);
create index if not exists ticket_appointments_technician_id_idx
    on public.ticket_appointments (technician_id);
create index if not exists ticket_appointments_ticket_id_idx
    on public.ticket_appointments (ticket_id);
create index if not exists ticket_logs_ticket_id_idx
    on public.ticket_logs (ticket_id);
create index if not exists workspaces_owner_id_idx
    on public.workspaces (owner_id);

-- Missing workspace relationships.
do $constraints$
begin
    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.checklist_templates'::regclass
           and conname = 'checklist_templates_workspace_id_fkey'
    ) then
        alter table public.checklist_templates
            add constraint checklist_templates_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.defect_options'::regclass
           and conname = 'defect_options_workspace_id_fkey'
    ) then
        alter table public.defect_options
            add constraint defect_options_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.defects'::regclass
           and conname = 'defects_workspace_id_fkey'
    ) then
        alter table public.defects
            add constraint defects_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.device_models'::regclass
           and conname = 'device_models_workspace_id_fkey'
    ) then
        alter table public.device_models
            add constraint device_models_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.internal_notes'::regclass
           and conname = 'internal_notes_workspace_id_fkey'
    ) then
        alter table public.internal_notes
            add constraint internal_notes_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.outsourced_companies'::regclass
           and conname = 'outsourced_companies_workspace_id_fkey'
    ) then
        alter table public.outsourced_companies
            add constraint outsourced_companies_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.terceirizados'::regclass
           and conname = 'terceirizados_workspace_id_fkey'
    ) then
        alter table public.terceirizados
            add constraint terceirizados_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.tickets'::regclass
           and conname = 'tickets_workspace_id_fkey'
    ) then
        alter table public.tickets
            add constraint tickets_workspace_id_fkey
            foreign key (workspace_id) references public.workspaces(id)
            on delete restrict not valid;
    end if;
end
$constraints$;

-- Workspace-aware relationships for objects that must belong to the same tenant.
do $tenant_constraints$
begin
    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.tickets'::regclass
           and conname = 'tickets_workspace_technician_fkey'
    ) then
        alter table public.tickets
            add constraint tickets_workspace_technician_fkey
            foreign key (workspace_id, technician_id)
            references public.employees(workspace_id, id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.tickets'::regclass
           and conname = 'tickets_workspace_outsourced_company_fkey'
    ) then
        alter table public.tickets
            add constraint tickets_workspace_outsourced_company_fkey
            foreign key (workspace_id, outsourced_company_id)
            references public.outsourced_companies(workspace_id, id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.internal_notes'::regclass
           and conname = 'internal_notes_workspace_ticket_fkey'
    ) then
        alter table public.internal_notes
            add constraint internal_notes_workspace_ticket_fkey
            foreign key (workspace_id, ticket_id)
            references public.tickets(workspace_id, id)
            on delete cascade not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.ticket_appointments'::regclass
           and conname = 'ticket_appointments_workspace_ticket_fkey'
    ) then
        alter table public.ticket_appointments
            add constraint ticket_appointments_workspace_ticket_fkey
            foreign key (workspace_id, ticket_id)
            references public.tickets(workspace_id, id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.ticket_appointments'::regclass
           and conname = 'ticket_appointments_workspace_technician_fkey'
    ) then
        alter table public.ticket_appointments
            add constraint ticket_appointments_workspace_technician_fkey
            foreign key (workspace_id, technician_id)
            references public.employees(workspace_id, id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.technician_schedule_blocks'::regclass
           and conname = 'technician_schedule_blocks_workspace_technician_fkey'
    ) then
        alter table public.technician_schedule_blocks
            add constraint technician_schedule_blocks_workspace_technician_fkey
            foreign key (workspace_id, technician_id)
            references public.employees(workspace_id, id)
            on delete restrict not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
         where conrelid = 'public.technician_schedule_settings'::regclass
           and conname = 'technician_schedule_settings_workspace_technician_fkey'
    ) then
        alter table public.technician_schedule_settings
            add constraint technician_schedule_settings_workspace_technician_fkey
            foreign key (workspace_id, technician_id)
            references public.employees(workspace_id, id)
            on delete restrict not valid;
    end if;
end
$tenant_constraints$;

-- Correct the legacy default and enforce the JSON shapes already used by the UI.
alter table public.tickets
    alter column checklist_data set default '[]'::jsonb;

do $value_constraints$
begin
    if not exists (select 1 from pg_constraint where conrelid='public.tickets'::regclass and conname='tickets_required_text_nonblank') then
        alter table public.tickets add constraint tickets_required_text_nonblank
            check (btrim(client_name) <> '' and btrim(os_number) <> '' and btrim(device_model) <> '') not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.workspaces'::regclass and conname='workspaces_required_text_nonblank') then
        alter table public.workspaces add constraint workspaces_required_text_nonblank
            check (btrim(name) <> '' and btrim(company_code) <> '') not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.employees'::regclass and conname='employees_required_text_nonblank') then
        alter table public.employees add constraint employees_required_text_nonblank
            check (btrim(name) <> '' and btrim(username) <> '') not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.defect_options'::regclass and conname='defect_options_name_nonblank') then
        alter table public.defect_options add constraint defect_options_name_nonblank check (btrim(name) <> '') not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.defects'::regclass and conname='defects_name_nonblank') then
        alter table public.defects add constraint defects_name_nonblank check (btrim(name) <> '') not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.device_models'::regclass and conname='device_models_name_nonblank') then
        alter table public.device_models add constraint device_models_name_nonblank check (btrim(name) <> '') not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.checklist_templates'::regclass and conname='checklist_templates_shape_check') then
        alter table public.checklist_templates add constraint checklist_templates_shape_check check (
            btrim(name) <> ''
            and type in ('entry', 'final')
            and jsonb_typeof(items) = 'array'
            and jsonb_array_length(items) > 0
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.internal_notes'::regclass and conname='internal_notes_checklist_shape_check') then
        alter table public.internal_notes add constraint internal_notes_checklist_shape_check check (
            checklist_data is null or jsonb_typeof(checklist_data) = 'array'
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.tickets'::regclass and conname='tickets_json_shapes_check') then
        alter table public.tickets add constraint tickets_json_shapes_check check (
            (checklist_data is null or jsonb_typeof(checklist_data) = 'array')
            and (test_notes is null or jsonb_typeof(test_notes) = 'array')
            and (checklist_final_data is null or jsonb_typeof(checklist_final_data) = 'array')
            and (outsourced_notes is null or jsonb_typeof(outsourced_notes) = 'array')
            and (supplier_purchases is null or jsonb_typeof(supplier_purchases) = 'array')
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.workspaces'::regclass and conname='workspaces_tracker_config_object_check') then
        alter table public.workspaces add constraint workspaces_tracker_config_object_check check (
            tracker_config is null or jsonb_typeof(tracker_config) = 'object'
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.technician_schedule_settings'::regclass and conname='technician_schedule_settings_settings_object_check') then
        alter table public.technician_schedule_settings add constraint technician_schedule_settings_settings_object_check check (
            settings is null or jsonb_typeof(settings) = 'object'
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.technician_schedule_blocks'::regclass and conname='technician_schedule_blocks_recurrence_days_array_check') then
        alter table public.technician_schedule_blocks add constraint technician_schedule_blocks_recurrence_days_array_check check (
            recurrence_days is null or jsonb_typeof(recurrence_days) = 'array'
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.tickets'::regclass and conname='tickets_counters_nonnegative_check') then
        alter table public.tickets add constraint tickets_counters_nonnegative_check check (
            repair_resume_count >= 0 and outsourced_return_count >= 0
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.tickets'::regclass and conname='tickets_budget_value_nonnegative_check') then
        alter table public.tickets add constraint tickets_budget_value_nonnegative_check check (
            budget_value is null or budget_value >= 0
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.employee_sessions'::regclass and conname='employee_sessions_date_order_check') then
        alter table public.employee_sessions add constraint employee_sessions_date_order_check check (
            expires_at > created_at and (revoked_at is null or revoked_at >= created_at)
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.ticket_appointments'::regclass and conname='ticket_appointments_actual_dates_check') then
        alter table public.ticket_appointments add constraint ticket_appointments_actual_dates_check check (
            actual_start is null or actual_end is null or actual_end >= actual_start
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.ticket_appointments'::regclass and conname='ticket_appointments_creator_identity_check') then
        alter table public.ticket_appointments add constraint ticket_appointments_creator_identity_check check (
            (created_by_user_id is null) <> (created_by_employee_id is null)
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.ticket_appointments'::regclass and conname='ticket_appointments_updater_identity_check') then
        alter table public.ticket_appointments add constraint ticket_appointments_updater_identity_check check (
            not (updated_by_user_id is not null and updated_by_employee_id is not null)
        ) not valid;
    end if;
    if not exists (select 1 from pg_constraint where conrelid='public.technician_schedule_blocks'::regclass and conname='technician_schedule_blocks_creator_identity_check') then
        alter table public.technician_schedule_blocks add constraint technician_schedule_blocks_creator_identity_check check (
            (created_by_user_id is null) <> (created_by_employee_id is null)
        ) not valid;
    end if;
end
$value_constraints$;

-- A unique index cannot be added yet because nine legacy OS-number groups are
-- duplicated. This trigger protects every new or deliberately changed number
-- without blocking unrelated updates to those historical rows.
create or replace function private.enforce_ticket_os_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_normalized_os text;
begin
    if new.deleted_at is not null then
        return new;
    end if;

    v_normalized_os := pg_catalog.lower(pg_catalog.btrim(new.os_number));
    if v_normalized_os is null or v_normalized_os = '' then
        raise exception using
            errcode = '23514',
            message = 'Informe o número da OS antes de salvar.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            pg_catalog.concat_ws(
                ':', 'aida_ticket_os', new.workspace_id::text, v_normalized_os
            ),
            0
        )
    );

    if exists (
        select 1
          from public.tickets t
         where t.workspace_id = new.workspace_id
           and t.deleted_at is null
           and pg_catalog.lower(pg_catalog.btrim(t.os_number)) = v_normalized_os
           and t.id <> new.id
    ) then
        raise exception using
            errcode = '23505',
            message = 'Já existe uma OS ativa com esse número nesta empresa.';
    end if;

    return new;
end;
$$;

revoke all on function private.enforce_ticket_os_integrity()
    from public, anon, authenticated, service_role;

drop trigger if exists zz_aida_enforce_ticket_os_integrity on public.tickets;
create trigger zz_aida_enforce_ticket_os_integrity
before insert or update of workspace_id, os_number, deleted_at
on public.tickets
for each row
execute function private.enforce_ticket_os_integrity();

-- Validate after the short NOT VALID additions so existing rows are checked once.
alter table public.checklist_templates validate constraint checklist_templates_workspace_id_fkey;
alter table public.defect_options validate constraint defect_options_workspace_id_fkey;
alter table public.defects validate constraint defects_workspace_id_fkey;
alter table public.device_models validate constraint device_models_workspace_id_fkey;
alter table public.internal_notes validate constraint internal_notes_workspace_id_fkey;
alter table public.outsourced_companies validate constraint outsourced_companies_workspace_id_fkey;
alter table public.terceirizados validate constraint terceirizados_workspace_id_fkey;
alter table public.tickets validate constraint tickets_workspace_id_fkey;
alter table public.tickets validate constraint tickets_workspace_technician_fkey;
alter table public.tickets validate constraint tickets_workspace_outsourced_company_fkey;
alter table public.internal_notes validate constraint internal_notes_workspace_ticket_fkey;
alter table public.ticket_appointments validate constraint ticket_appointments_workspace_ticket_fkey;
alter table public.ticket_appointments validate constraint ticket_appointments_workspace_technician_fkey;
alter table public.technician_schedule_blocks validate constraint technician_schedule_blocks_workspace_technician_fkey;
alter table public.technician_schedule_settings validate constraint technician_schedule_settings_workspace_technician_fkey;

alter table public.tickets validate constraint tickets_required_text_nonblank;
alter table public.workspaces validate constraint workspaces_required_text_nonblank;
alter table public.employees validate constraint employees_required_text_nonblank;
alter table public.defect_options validate constraint defect_options_name_nonblank;
alter table public.defects validate constraint defects_name_nonblank;
alter table public.device_models validate constraint device_models_name_nonblank;
alter table public.checklist_templates validate constraint checklist_templates_shape_check;
alter table public.internal_notes validate constraint internal_notes_checklist_shape_check;
alter table public.tickets validate constraint tickets_json_shapes_check;
alter table public.workspaces validate constraint workspaces_tracker_config_object_check;
alter table public.technician_schedule_settings validate constraint technician_schedule_settings_settings_object_check;
alter table public.technician_schedule_blocks validate constraint technician_schedule_blocks_recurrence_days_array_check;
alter table public.tickets validate constraint tickets_counters_nonnegative_check;
alter table public.tickets validate constraint tickets_budget_value_nonnegative_check;
alter table public.employee_sessions validate constraint employee_sessions_date_order_check;
alter table public.ticket_appointments validate constraint ticket_appointments_actual_dates_check;
alter table public.ticket_appointments validate constraint ticket_appointments_creator_identity_check;
alter table public.ticket_appointments validate constraint ticket_appointments_updater_identity_check;
alter table public.technician_schedule_blocks validate constraint technician_schedule_blocks_creator_identity_check;

commit;
