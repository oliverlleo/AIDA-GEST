begin;

create or replace function private.inventory_resume_ready_ticket(
    p_workspace_id uuid,
    p_ticket_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ctx record;
    v_ticket public.tickets%rowtype;
    v_config jsonb;
    v_timer boolean;
    v_ready boolean;
    v_schedule_enabled boolean;
    v_has_repair_appointment boolean;
    v_is_resuming boolean;
    v_schedule_required boolean;
begin
    select * into v_ctx from public.get_current_actor_context();

    if v_ctx.workspace_id is distinct from p_workspace_id then
        raise exception 'Acesso negado ao chamado.';
    end if;

    select * into v_ticket
    from public.tickets t
    where t.workspace_id = p_workspace_id
      and t.id = p_ticket_id
      and t.deleted_at is null
    for update;
    if not found then
        return jsonb_build_object('ready', false);
    end if;

    select not exists (
        select 1
        from public.ticket_part_items tp
        where tp.workspace_id = p_workspace_id
          and tp.ticket_id = p_ticket_id
          and tp.status in ('needed', 'pending_approval', 'partial', 'purchase_pending')
    )
    into v_ready;

    if not v_ready then
        return jsonb_build_object(
            'ready', false,
            'status', v_ticket.status,
            'schedule_required', false
        );
    end if;

    update public.ticket_part_items
    set status = 'ready',
        updated_at = now()
    where workspace_id = p_workspace_id
      and ticket_id = p_ticket_id
      and status = 'reserved';

    select coalesce(w.tracker_config, '{}'::jsonb)
    into v_config
    from public.workspaces w
    where w.id = p_workspace_id;

    v_timer := public.aida_config_bool(
        v_config, 'workflow', 'repair_timer', true
    );
    v_schedule_enabled :=
        public.aida_config_bool(v_config, 'modules', 'agenda', true)
        and public.aida_ticket_field_mode(
            v_config, 'repair_schedule', false
        ) <> 'disabled';
    v_is_resuming := v_ticket.repair_paused_at is not null;

    select exists (
        select 1
        from public.ticket_appointments a
        where a.workspace_id = p_workspace_id
          and a.ticket_id = p_ticket_id
          and a.appointment_type = 'repair'
          and a.status in ('scheduled', 'in_progress')
          and a.deleted_at is null
    )
    into v_has_repair_appointment;

    v_schedule_required :=
        v_schedule_enabled
        and not v_has_repair_appointment
        and not v_is_resuming;

    update public.tickets
    set status = 'Andamento Reparo',
        parts_status = 'Recebido',
        parts_received_at = coalesce(parts_received_at, now()),
        repair_paused_at = null,
        repair_start_at = case
            when v_is_resuming then now()
            else repair_start_at
        end,
        repair_elapsed_seconds = case
            when v_timer then coalesce(repair_elapsed_seconds, 0)
            else 0
        end,
        repair_resume_count = case
            when v_is_resuming
                then coalesce(repair_resume_count, 0) + 1
            else repair_resume_count
        end,
        updated_at = now()
    where workspace_id = p_workspace_id
      and id = p_ticket_id;

    insert into public.ticket_logs(ticket_id, action, details, user_name)
    values (
        p_ticket_id,
        case
            when v_is_resuming then 'Retomou Reparo após Compra'
            when v_schedule_required then 'Recebeu Peças'
            else 'Liberou Reparo após Agendamento'
        end,
        format(
            case
                when v_is_resuming then
                    'Todas as peças da **OS %s** foram recebidas e reservadas. O reparo foi retomado por **%s**.%s'
                when v_schedule_required then
                    'Todas as peças da **OS %s** foram recebidas e reservadas por **%s**. A OS foi enviada para **Em Reparo** e aguarda agendamento.%s'
                else
                    'O reparo da **OS %s** foi agendado e liberado por **%s**.%s'
            end,
            coalesce(v_ticket.os_number, 'não informada'),
            v_ctx.actor_name,
            case
                when v_is_resuming and v_timer then format(
                    ' O cronômetro continuou dos **%s segundos** já acumulados.',
                    coalesce(v_ticket.repair_elapsed_seconds, 0)
                )
                else ''
            end
        ),
        v_ctx.actor_name
    );

    return jsonb_build_object(
        'ready', true,
        'status', 'Andamento Reparo',
        'resumed', v_is_resuming,
        'schedule_required', v_schedule_required
    );
end;
$$;

revoke all on function private.inventory_resume_ready_ticket(uuid, uuid)
from public, anon, authenticated, service_role;

create or replace function private.inventory_release_ticket_after_repair_schedule()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ticket public.tickets%rowtype;
begin
    if new.appointment_type <> 'repair'
       or new.status not in ('scheduled', 'in_progress')
       or new.deleted_at is not null then
        return new;
    end if;

    if tg_op = 'UPDATE' then
        if old.status in ('scheduled', 'in_progress')
           and old.deleted_at is null then
            return new;
        end if;
    end if;

    select * into v_ticket
    from public.tickets t
    where t.workspace_id = new.workspace_id
      and t.id = new.ticket_id
      and t.deleted_at is null
    for update;

    if found
       and v_ticket.status = 'Compra Peca'
       and v_ticket.parts_status = 'Recebido'
       and v_ticket.repair_paused_at is null
       and not exists (
           select 1
           from public.ticket_part_items tp
           where tp.workspace_id = new.workspace_id
             and tp.ticket_id = new.ticket_id
             and tp.status in (
                 'needed', 'pending_approval', 'partial', 'purchase_pending'
             )
       ) then
        perform private.inventory_resume_ready_ticket(
            new.workspace_id,
            new.ticket_id
        );
    end if;

    return new;
end;
$$;

revoke all on function private.inventory_release_ticket_after_repair_schedule()
from public, anon, authenticated, service_role;

-- Corrige OS recebidas por versões anteriores: elas pertencem ao quadro
-- Em Reparo mesmo quando o usuário fecha o painel sem escolher uma data.
with moved as (
    update public.tickets t
    set status = 'Andamento Reparo',
        updated_at = now()
    from public.workspaces w
    where w.id = t.workspace_id
      and t.deleted_at is null
      and t.status = 'Compra Peca'
      and t.parts_status = 'Recebido'
      and t.repair_paused_at is null
      and public.aida_config_bool(
          coalesce(w.tracker_config, '{}'::jsonb),
          'modules',
          'inventory',
          false
      )
      and not exists (
          select 1
          from public.ticket_part_items tp
          where tp.workspace_id = t.workspace_id
            and tp.ticket_id = t.id
            and tp.status in (
                'needed', 'pending_approval', 'partial', 'purchase_pending'
            )
      )
    returning t.id, t.os_number
)
insert into public.ticket_logs(ticket_id, action, details, user_name)
select
    moved.id,
    'Liberou Reparo após Recebimento',
    format(
        'A **OS %s** foi movida automaticamente para **Em Reparo** após o recebimento integral das peças. O cronômetro não foi iniciado.',
        coalesce(moved.os_number, 'não informada')
    ),
    'Sistema'
from moved;

drop trigger if exists trg_inventory_release_after_repair_schedule
on public.ticket_appointments;

create trigger trg_inventory_release_after_repair_schedule
after insert or update of status, deleted_at
on public.ticket_appointments
for each row
execute function private.inventory_release_ticket_after_repair_schedule();

commit;
