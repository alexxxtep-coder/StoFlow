-- STO.Flow 6.0: transactional operations used by the new server actions.
-- Apply after 0001_initial_schema.sql in the same Supabase project.

-- Align resource and membership visibility with the server-side role model.
drop policy if exists tenant_insert on public.resources;
drop policy if exists tenant_update on public.resources;
drop policy if exists resources_insert on public.resources;
drop policy if exists resources_update on public.resources;
create policy resources_insert on public.resources for insert
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[]));
create policy resources_update on public.resources for update
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[]));

drop policy if exists memberships_select on public.memberships;
create policy memberships_select on public.memberships for select
  using (user_id = auth.uid() or public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[]));

-- Restore least-privilege INSERT access even if an earlier standalone SQL patch
-- broadened these policies to every role.
drop policy if exists customers_insert on public.customers;
create policy customers_insert on public.customers for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
drop policy if exists vehicles_insert on public.vehicles;
create policy vehicles_insert on public.vehicles for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
drop policy if exists leads_insert on public.leads;
create policy leads_insert on public.leads for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);

create or replace function public.add_work_order_line_with_financials(
  p_tenant_id uuid,
  p_work_order_id uuid,
  p_line_type text,
  p_description text,
  p_quantity numeric,
  p_customer_unit_price numeric,
  p_direct_unit_cost numeric default 0
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  new_line uuid;
begin
  if not public.has_tenant_role(p_tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]) then
    raise exception 'Permission denied';
  end if;
  if p_line_type not in ('labor','part','other') then raise exception 'Invalid line type'; end if;
  if nullif(trim(coalesce(p_description,'')),'') is null then raise exception 'Description is required'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
  if p_customer_unit_price is null or p_customer_unit_price < 0 then raise exception 'Invalid customer price'; end if;
  if p_direct_unit_cost is null or p_direct_unit_cost < 0 then raise exception 'Invalid direct cost'; end if;
  perform 1 from public.work_orders where id=p_work_order_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Work order not found'; end if;

  insert into public.work_order_lines(tenant_id,work_order_id,line_type,description,quantity)
  values(p_tenant_id,p_work_order_id,p_line_type,trim(p_description),p_quantity)
  returning id into new_line;
  insert into public.work_order_line_financials(tenant_id,work_order_line_id,customer_unit_price,direct_unit_cost)
  values(p_tenant_id,new_line,p_customer_unit_price,p_direct_unit_cost);
  return new_line;
end;
$$;

create or replace function public.create_payment_with_allocation(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_currency text,
  p_payment_method text,
  p_reference text default null,
  p_work_order_id uuid default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  new_payment uuid;
begin
  if not public.has_tenant_role(p_tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]) then
    raise exception 'Permission denied';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
  if not exists(select 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id) then
    raise exception 'Customer not found';
  end if;
  if p_work_order_id is not null and not exists(
    select 1 from public.work_orders where id=p_work_order_id and tenant_id=p_tenant_id and customer_id=p_customer_id
  ) then raise exception 'Work order does not belong to customer'; end if;

  insert into public.payments(tenant_id,customer_id,amount,currency,payment_method,reference,created_by)
  values(p_tenant_id,p_customer_id,p_amount,p_currency,p_payment_method,nullif(trim(coalesce(p_reference,'')),''),auth.uid())
  returning id into new_payment;
  if p_work_order_id is not null then
    insert into public.payment_allocations(tenant_id,payment_id,work_order_id,amount)
    values(p_tenant_id,new_payment,p_work_order_id,p_amount);
  end if;
  return new_payment;
end;
$$;

revoke all on function public.add_work_order_line_with_financials(uuid,uuid,text,text,numeric,numeric,numeric) from public, anon;
revoke all on function public.create_payment_with_allocation(uuid,uuid,numeric,text,text,text,uuid) from public, anon;
grant execute on function public.add_work_order_line_with_financials(uuid,uuid,text,text,numeric,numeric,numeric) to authenticated;
grant execute on function public.create_payment_with_allocation(uuid,uuid,numeric,text,text,text,uuid) to authenticated;

-- Harden lead phone validation: punctuation and a leading '+' are ignored when counting digits.
-- The initial migration declared the same type signature with a different argument
-- order/names. PostgreSQL cannot rename input parameters with CREATE OR REPLACE;
-- drop the exact signature first, then recreate it in the order used by the app.
drop function if exists public.create_lead_with_context(uuid,text,text,text,text,text,text,text,text);
create function public.create_lead_with_context(
  p_tenant_id uuid, p_customer_name text, p_phone text,
  p_vehicle_make text default null, p_vehicle_model text default null,
  p_plate text default null, p_vin text default null,
  p_description text default null, p_source text default 'other'
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  customer_uuid uuid;
  vehicle_uuid uuid;
  lead_uuid uuid;
  normalized text;
begin
  if not public.has_tenant_role(p_tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]) then raise exception 'Permission denied'; end if;
  if char_length(trim(coalesce(p_customer_name,''))) < 2 then raise exception 'Customer name is required'; end if;
  normalized := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  if char_length(regexp_replace(normalized, '[^0-9]', '', 'g')) < 5 then
    raise exception 'Phone must contain at least five digits';
  end if;
  if char_length(trim(coalesce(p_description,''))) < 3 then raise exception 'Description is required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':' || normalized, 0));
  select id into customer_uuid from public.customers
    where tenant_id=p_tenant_id and normalized_phone=normalized
    order by created_at asc limit 1 for update;
  if customer_uuid is null then
    insert into public.customers(tenant_id,name,normalized_phone,created_by)
    values(p_tenant_id,trim(p_customer_name),normalized,auth.uid())
    returning id into customer_uuid;
  end if;

  if nullif(trim(coalesce(p_vehicle_make,'')),'') is not null
     or nullif(trim(coalesce(p_vehicle_model,'')),'') is not null
     or nullif(trim(coalesce(p_plate,'')),'') is not null
     or nullif(trim(coalesce(p_vin,'')),'') is not null then
    if nullif(trim(coalesce(p_vin,'')),'') is not null then
      select id into vehicle_uuid from public.vehicles
        where tenant_id=p_tenant_id and customer_id=customer_uuid and upper(vin)=upper(trim(p_vin))
        limit 1 for update;
    elsif nullif(trim(coalesce(p_plate,'')),'') is not null then
      select id into vehicle_uuid from public.vehicles
        where tenant_id=p_tenant_id and customer_id=customer_uuid and upper(plate)=upper(trim(p_plate))
        limit 1 for update;
    end if;
    if vehicle_uuid is null then
      insert into public.vehicles(tenant_id,customer_id,make,model,plate,vin,vehicle_identity_source,identity_confidence)
      values(p_tenant_id,customer_uuid,nullif(trim(p_vehicle_make),''),nullif(trim(p_vehicle_model),''),
        nullif(trim(p_plate),''),nullif(upper(trim(p_vin)),''),'manual','unverified')
      returning id into vehicle_uuid;
    end if;
  end if;

  insert into public.leads(tenant_id,customer_id,vehicle_id,description,source,created_by,owner_user_id)
  values(p_tenant_id,customer_uuid,vehicle_uuid,trim(p_description),p_source,auth.uid(),auth.uid())
  returning id into lead_uuid;
  return lead_uuid;
end;
$$;

revoke all on function public.create_lead_with_context(uuid,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.create_lead_with_context(uuid,text,text,text,text,text,text,text,text) to authenticated;
