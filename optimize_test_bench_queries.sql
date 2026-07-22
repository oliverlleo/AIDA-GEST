-- Stage 7.4: bounded keyset pages for the final-test bench.
--
-- The workspace is resolved from the current actor. SECURITY INVOKER keeps the
-- existing ticket RLS rules in force for admins, attendants, testers and techs.

begin;

create index if not exists idx_tickets_test_bench_queue
    on public.tickets (
        workspace_id,
        (case when priority_requested is true then 0 else 1 end),
        (case when deadline is null then 1 else 0 end),
        deadline,
        (case when test_start_at is null then 1 else 0 end),
        test_start_at,
        created_at,
        id
    )
    where deleted_at is null
      and status = 'Teste Final';

create or replace function public.get_test_bench_page(
    p_limit integer default 20,
    p_cursor jsonb default null,
    p_use_priority boolean default true,
    p_use_delivery_deadline boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_ctx record;
    v_cursor_priority integer;
    v_cursor_deadline_rank integer;
    v_cursor_deadline_at timestamptz;
    v_cursor_test_rank integer;
    v_cursor_test_at timestamptz;
    v_cursor_created_at timestamptz;
    v_cursor_id uuid;
    v_result jsonb;
begin
    select * into v_ctx from public.get_current_actor_context();

    if p_limit is null or p_limit < 1 or p_limit > 50 then
        raise exception 'O limite deve estar entre 1 e 50.';
    end if;

    if p_cursor is not null then
        begin
            v_cursor_priority := (p_cursor ->> 'priority_rank')::integer;
            v_cursor_deadline_rank := (p_cursor ->> 'deadline_rank')::integer;
            v_cursor_deadline_at := (p_cursor ->> 'deadline_at')::timestamptz;
            v_cursor_test_rank := (p_cursor ->> 'test_rank')::integer;
            v_cursor_test_at := (p_cursor ->> 'test_at')::timestamptz;
            v_cursor_created_at := (p_cursor ->> 'created_at')::timestamptz;
            v_cursor_id := (p_cursor ->> 'id')::uuid;
        exception when others then
            raise exception 'Cursor de paginacao invalido.';
        end;

        if v_cursor_priority is null or v_cursor_deadline_rank is null
           or v_cursor_deadline_at is null or v_cursor_test_rank is null
           or v_cursor_test_at is null or v_cursor_created_at is null
           or v_cursor_id is null then
            raise exception 'Cursor de paginacao incompleto.';
        end if;
    end if;

    with base as materialized (
        select
            t.id,
            t.workspace_id,
            t.os_number,
            t.client_name,
            t.device_model,
            t.priority,
            t.priority_requested,
            t.technician_id,
            t.defect_reported,
            t.test_start_at,
            t.deadline,
            t.status,
            t.created_at,
            case
                when coalesce(p_use_priority, true)
                     and t.priority_requested is true then 0
                else 1
            end as priority_rank,
            case
                when coalesce(p_use_delivery_deadline, true) and t.deadline is not null then 0
                else 1
            end as deadline_rank,
            coalesce(
                case when coalesce(p_use_delivery_deadline, true) then t.deadline end,
                'infinity'::timestamptz
            ) as deadline_sort_at,
            case when t.test_start_at is null then 1 else 0 end as test_rank,
            coalesce(t.test_start_at, 'infinity'::timestamptz) as test_sort_at
        from public.tickets t
        where t.workspace_id = v_ctx.workspace_id
          and t.deleted_at is null
          and t.status = 'Teste Final'
    ), after_cursor as (
        select *
        from base b
        where p_cursor is null
           or (
                b.priority_rank, b.deadline_rank, b.deadline_sort_at,
                b.test_rank, b.test_sort_at, b.created_at, b.id
              ) > (
                v_cursor_priority, v_cursor_deadline_rank, v_cursor_deadline_at,
                v_cursor_test_rank, v_cursor_test_at, v_cursor_created_at, v_cursor_id
              )
    ), page_plus_one as materialized (
        select *
        from after_cursor
        order by priority_rank, deadline_rank, deadline_sort_at,
                 test_rank, test_sort_at, created_at, id
        limit p_limit + 1
    ), page_rows as materialized (
        select *
        from page_plus_one
        order by priority_rank, deadline_rank, deadline_sort_at,
                 test_rank, test_sort_at, created_at, id
        limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(
                (to_jsonb(p) - 'priority_rank' - 'deadline_rank' - 'deadline_sort_at'
                    - 'test_rank' - 'test_sort_at')
                || jsonb_build_object('_card_summary', true)
                order by p.priority_rank, p.deadline_rank, p.deadline_sort_at,
                         p.test_rank, p.test_sort_at, p.created_at, p.id
            )
            from page_rows p
        ), '[]'::jsonb),
        'total', (select count(*) from base),
        'has_more', (select count(*) > p_limit from page_plus_one),
        'next_cursor', case
            when not (select count(*) > p_limit from page_plus_one) then null
            else (
                select jsonb_build_object(
                    'priority_rank', p.priority_rank,
                    'deadline_rank', p.deadline_rank,
                    'deadline_at', p.deadline_sort_at,
                    'test_rank', p.test_rank,
                    'test_at', p.test_sort_at,
                    'created_at', p.created_at,
                    'id', p.id
                )
                from page_rows p
                order by p.priority_rank desc, p.deadline_rank desc,
                         p.deadline_sort_at desc, p.test_rank desc,
                         p.test_sort_at desc, p.created_at desc, p.id desc
                limit 1
            )
        end
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.get_test_bench_page(integer, jsonb, boolean, boolean)
from public;
grant execute on function public.get_test_bench_page(integer, jsonb, boolean, boolean)
to anon, authenticated;

comment on function public.get_test_bench_page(integer, jsonb, boolean, boolean)
is 'Returns one RLS-protected keyset page of lightweight final-test cards for the current workspace.';

commit;
