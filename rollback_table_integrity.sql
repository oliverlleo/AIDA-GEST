-- Emergency rollback for harden_table_integrity.sql.

begin;

drop trigger if exists zz_aida_enforce_ticket_os_integrity on public.tickets;
drop function if exists private.enforce_ticket_os_integrity();

alter table public.tickets
    alter column checklist_data set default '{}'::jsonb;

alter table public.technician_schedule_blocks drop constraint if exists technician_schedule_blocks_creator_identity_check;
alter table public.ticket_appointments drop constraint if exists ticket_appointments_updater_identity_check;
alter table public.ticket_appointments drop constraint if exists ticket_appointments_creator_identity_check;
alter table public.ticket_appointments drop constraint if exists ticket_appointments_actual_dates_check;
alter table public.employee_sessions drop constraint if exists employee_sessions_date_order_check;
alter table public.tickets drop constraint if exists tickets_budget_value_nonnegative_check;
alter table public.tickets drop constraint if exists tickets_counters_nonnegative_check;
alter table public.technician_schedule_blocks drop constraint if exists technician_schedule_blocks_recurrence_days_array_check;
alter table public.technician_schedule_settings drop constraint if exists technician_schedule_settings_settings_object_check;
alter table public.workspaces drop constraint if exists workspaces_tracker_config_object_check;
alter table public.tickets drop constraint if exists tickets_json_shapes_check;
alter table public.internal_notes drop constraint if exists internal_notes_checklist_shape_check;
alter table public.checklist_templates drop constraint if exists checklist_templates_shape_check;
alter table public.device_models drop constraint if exists device_models_name_nonblank;
alter table public.defects drop constraint if exists defects_name_nonblank;
alter table public.defect_options drop constraint if exists defect_options_name_nonblank;
alter table public.employees drop constraint if exists employees_required_text_nonblank;
alter table public.workspaces drop constraint if exists workspaces_required_text_nonblank;
alter table public.tickets drop constraint if exists tickets_required_text_nonblank;

alter table public.technician_schedule_settings drop constraint if exists technician_schedule_settings_workspace_technician_fkey;
alter table public.technician_schedule_blocks drop constraint if exists technician_schedule_blocks_workspace_technician_fkey;
alter table public.ticket_appointments drop constraint if exists ticket_appointments_workspace_technician_fkey;
alter table public.ticket_appointments drop constraint if exists ticket_appointments_workspace_ticket_fkey;
alter table public.internal_notes drop constraint if exists internal_notes_workspace_ticket_fkey;
alter table public.tickets drop constraint if exists tickets_workspace_outsourced_company_fkey;
alter table public.tickets drop constraint if exists tickets_workspace_technician_fkey;
alter table public.tickets drop constraint if exists tickets_workspace_id_fkey;
alter table public.terceirizados drop constraint if exists terceirizados_workspace_id_fkey;
alter table public.outsourced_companies drop constraint if exists outsourced_companies_workspace_id_fkey;
alter table public.internal_notes drop constraint if exists internal_notes_workspace_id_fkey;
alter table public.device_models drop constraint if exists device_models_workspace_id_fkey;
alter table public.defects drop constraint if exists defects_workspace_id_fkey;
alter table public.defect_options drop constraint if exists defect_options_workspace_id_fkey;
alter table public.checklist_templates drop constraint if exists checklist_templates_workspace_id_fkey;

drop index if exists public.workspaces_owner_id_idx;
drop index if exists public.tickets_workspace_outsourced_company_idx;
drop index if exists public.ticket_logs_ticket_id_idx;
drop index if exists public.ticket_appointments_ticket_id_idx;
drop index if exists public.ticket_appointments_technician_id_idx;
drop index if exists public.terceirizados_workspace_id_idx;
drop index if exists public.technician_schedule_blocks_technician_id_idx;
drop index if exists public.suppliers_workspace_id_idx;
drop index if exists public.profiles_workspace_id_idx;
drop index if exists public.outsourced_companies_workspace_id_idx;
drop index if exists public.notifications_ticket_id_idx;
drop index if exists public.internal_notes_workspace_id_idx;
drop index if exists public.internal_notes_workspace_ticket_idx;
drop index if exists public.internal_notes_ticket_id_idx;
drop index if exists public.fornecedores_workspace_id_idx;
drop index if exists public.checklist_templates_workspace_id_idx;

drop index if exists public.outsourced_companies_workspace_id_id_uidx;
drop index if exists public.tickets_workspace_id_id_uidx;
drop index if exists public.employees_workspace_id_id_uidx;
drop index if exists public.checklist_templates_workspace_type_name_ci_uidx;
drop index if exists public.device_models_workspace_name_ci_uidx;
drop index if exists public.defects_workspace_name_ci_uidx;
drop index if exists public.defect_options_workspace_name_ci_uidx;
drop index if exists public.workspaces_company_code_ci_uidx;
drop index if exists public.employees_workspace_username_ci_uidx;

insert into public.defect_options (id, workspace_id, name, created_at)
select restored.id, restored.workspace_id, restored.name, restored.created_at
  from private.security_stage_backups b
  cross join lateral jsonb_to_recordset(
      coalesce(b.snapshot->'quarantined_rows'->'defect_options', '[]'::jsonb)
  ) as restored(id uuid, workspace_id uuid, name text, created_at timestamptz)
 where b.id = '655109f2-0f3d-48fb-8eb1-f901bcee8578'::uuid
   and b.label = 'pre_table_integrity_20260721'
on conflict (id) do nothing;

commit;
