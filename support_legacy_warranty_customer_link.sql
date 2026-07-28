begin;

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

commit;
