-- STO.Flow 6.0 — procurement safety guards.
-- Apply after 0001, 0002 and 0003. No existing purchase or offer rows are modified.

create or replace function public.add_manual_supplier_offer(
  p_tenant_id uuid,
  p_part_request_id uuid,
  p_supplier_name text,
  p_title text,
  p_brand text default null,
  p_sku text default null,
  p_purchase_price numeric default null,
  p_currency text default 'BYN',
  p_availability text default 'unknown',
  p_eta_at timestamptz default null,
  p_fitment_status text default 'unverified'
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
declare
  supplier_uuid uuid;
  offer_uuid uuid;
  request_status public.part_request_status;
  workspace_currency text;
begin
  if auth.uid() is null or not public.has_tenant_role(
    p_tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]
  ) then
    raise exception 'Permission denied';
  end if;

  if char_length(trim(coalesce(p_supplier_name,''))) < 2
     or char_length(trim(coalesce(p_supplier_name,''))) > 120
     or char_length(trim(coalesce(p_title,''))) < 2
     or char_length(trim(coalesce(p_title,''))) > 160 then
    raise exception 'Supplier and offer title are required and must fit the allowed length';
  end if;

  if p_purchase_price is not null and (
    p_purchase_price < 0 or p_purchase_price > 100000000
    or p_purchase_price <> round(p_purchase_price, 2)
  ) then
    raise exception 'Purchase price must be non-negative and have at most two decimal places';
  end if;

  select upper(trim(t.currency)) into workspace_currency
  from public.tenants t where t.id = p_tenant_id;
  if workspace_currency is null then raise exception 'Workspace not found'; end if;
  if upper(trim(coalesce(p_currency,''))) <> workspace_currency then
    raise exception 'Offer currency must match workspace currency';
  end if;

  select pr.status into request_status
  from public.part_requests pr
  where pr.id = p_part_request_id and pr.tenant_id = p_tenant_id
  for update;
  if not found then raise exception 'Part request not found'; end if;
  if request_status in ('received','cancelled') then
    raise exception 'Cannot add an offer to a received or cancelled part request';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':' || lower(trim(p_supplier_name)), 0
  ));
  select s.id into supplier_uuid
  from public.suppliers s
  where s.tenant_id = p_tenant_id and lower(s.name) = lower(trim(p_supplier_name))
  limit 1;

  if supplier_uuid is null then
    insert into public.suppliers(tenant_id,name,integration_status)
    values (p_tenant_id,trim(p_supplier_name),'manual_only')
    returning id into supplier_uuid;
  end if;

  insert into public.supplier_offers(
    tenant_id,part_request_id,supplier_id,brand,sku,title,purchase_price,currency,
    availability,eta_at,fitment_status,source_type,source_reference,observed_at,status
  ) values (
    p_tenant_id,p_part_request_id,supplier_uuid,nullif(trim(p_brand),''),nullif(trim(p_sku),''),
    trim(p_title),p_purchase_price,workspace_currency,p_availability,p_eta_at,p_fitment_status,
    'manual','manual entry',now(),'received'
  ) returning id into offer_uuid;

  return offer_uuid;
end;
$$;

revoke all on function public.add_manual_supplier_offer(uuid,uuid,text,text,text,text,numeric,text,text,timestamptz,text) from public, anon;
grant execute on function public.add_manual_supplier_offer(uuid,uuid,text,text,text,text,numeric,text,text,timestamptz,text) to authenticated;


create or replace function public.create_purchase_from_offer(p_tenant_id uuid, p_offer_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
declare
  chosen_offer public.supplier_offers%rowtype;
  chosen_request public.part_requests%rowtype;
  existing_purchase uuid;
  new_purchase uuid;
  workspace_currency text;
begin
  if auth.uid() is null or not public.has_tenant_role(
    p_tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]
  ) then
    raise exception 'Permission denied';
  end if;

  select * into chosen_offer
  from public.supplier_offers
  where id = p_offer_id and tenant_id = p_tenant_id
  for update;
  if not found then raise exception 'Offer not found'; end if;

  -- Idempotent retry: return the purchase already created for this offer.
  select p.id into existing_purchase
  from public.purchases p
  where p.tenant_id = p_tenant_id and p.supplier_offer_id = chosen_offer.id;
  if existing_purchase is not null then return existing_purchase; end if;

  select * into chosen_request
  from public.part_requests
  where id = chosen_offer.part_request_id and tenant_id = p_tenant_id
  for update;
  if not found then raise exception 'Part request not found'; end if;

  if chosen_request.status in ('received','cancelled') then
    raise exception 'Cannot purchase an offer for a received or cancelled part request';
  end if;
  if exists (
    select 1 from public.purchases p
    where p.tenant_id = p_tenant_id
      and p.part_request_id = chosen_request.id
      and p.supplier_offer_id is distinct from chosen_offer.id
  ) then
    raise exception 'A purchase already exists for this part request';
  end if;
  if chosen_offer.status in ('rejected','stale','accepted') then
    raise exception 'Offer is not available for a new purchase';
  end if;
  if chosen_offer.fitment_status = 'not_fit' then
    raise exception 'Cannot purchase an offer marked as not fitting the vehicle';
  end if;
  if chosen_offer.availability = 'out_of_stock' then
    raise exception 'Cannot purchase an offer marked out of stock';
  end if;
  if chosen_offer.purchase_price is null then
    raise exception 'Purchase price is required before creating a purchase';
  end if;

  select upper(trim(t.currency)) into workspace_currency
  from public.tenants t where t.id = p_tenant_id;
  if workspace_currency is null or upper(trim(chosen_offer.currency)) <> workspace_currency then
    raise exception 'Offer currency does not match workspace currency';
  end if;

  insert into public.purchases(
    tenant_id,supplier_id,part_request_id,supplier_offer_id,status,ordered_at,expected_at
  ) values (
    p_tenant_id,chosen_offer.supplier_id,chosen_offer.part_request_id,chosen_offer.id,
    'ordered',now(),chosen_offer.eta_at
  )
  on conflict (tenant_id,supplier_offer_id) do nothing
  returning id into new_purchase;

  if new_purchase is null then
    select p.id into new_purchase from public.purchases p
    where p.tenant_id = p_tenant_id and p.supplier_offer_id = chosen_offer.id;
  end if;

  update public.supplier_offers set status = 'accepted'
  where id = p_offer_id and tenant_id = p_tenant_id;
  update public.part_requests set status = 'ordered'
  where id = chosen_offer.part_request_id and tenant_id = p_tenant_id;

  return new_purchase;
end;
$$;

revoke all on function public.create_purchase_from_offer(uuid,uuid) from public, anon;
grant execute on function public.create_purchase_from_offer(uuid,uuid) to authenticated;


-- Enforce procurement invariants even if an authenticated client writes directly
-- to the exposed purchases table instead of calling create_purchase_from_offer.
create or replace function public.guard_purchase_insert()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
declare
  chosen_offer public.supplier_offers%rowtype;
  chosen_request public.part_requests%rowtype;
  workspace_currency text;
begin
  if auth.uid() is null or not public.has_tenant_role(
    new.tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]
  ) then
    raise exception 'Permission denied';
  end if;
  if new.status <> 'ordered' then
    raise exception 'A purchase can only be created in ordered status';
  end if;
  if new.supplier_offer_id is null or new.part_request_id is null or new.supplier_id is null then
    raise exception 'A purchase must reference its supplier, part request and supplier offer';
  end if;

  select * into chosen_offer
  from public.supplier_offers
  where id = new.supplier_offer_id and tenant_id = new.tenant_id
  for update;
  if not found then raise exception 'Supplier offer not found'; end if;

  select * into chosen_request
  from public.part_requests
  where id = new.part_request_id and tenant_id = new.tenant_id
  for update;
  if not found then raise exception 'Part request not found'; end if;

  if chosen_offer.part_request_id <> chosen_request.id
     or chosen_offer.supplier_id is distinct from new.supplier_id then
    raise exception 'Purchase references do not match the selected supplier offer';
  end if;
  if chosen_request.status in ('received','cancelled') then
    raise exception 'Cannot purchase an offer for a received or cancelled part request';
  end if;
  if chosen_offer.status in ('rejected','stale','accepted') then
    raise exception 'Offer is not available for a new purchase';
  end if;
  if chosen_offer.fitment_status = 'not_fit' then
    raise exception 'Cannot purchase an offer marked as not fitting the vehicle';
  end if;
  if chosen_offer.availability = 'out_of_stock' then
    raise exception 'Cannot purchase an offer marked out of stock';
  end if;
  if chosen_offer.purchase_price is null then
    raise exception 'Purchase price is required before creating a purchase';
  end if;

  select upper(trim(t.currency)) into workspace_currency
  from public.tenants t where t.id = new.tenant_id;
  if workspace_currency is null or upper(trim(chosen_offer.currency)) <> workspace_currency then
    raise exception 'Offer currency does not match workspace currency';
  end if;

  if exists (
    select 1 from public.purchases p
    where p.tenant_id = new.tenant_id and p.part_request_id = new.part_request_id
  ) then
    raise exception 'A purchase already exists for this part request';
  end if;
  return new;
end;
$$;

create or replace function public.sync_purchase_request_status()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
begin
  update public.supplier_offers
  set status = 'accepted'
  where id = new.supplier_offer_id and tenant_id = new.tenant_id;
  update public.part_requests
  set status = 'ordered'
  where id = new.part_request_id and tenant_id = new.tenant_id;
  return new;
end;
$$;

create or replace function public.prevent_direct_purchase_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if auth.uid() is not null then
    raise exception 'Purchase updates and deletion require an approved receiving workflow';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists purchases_guard_insert on public.purchases;
create trigger purchases_guard_insert
before insert on public.purchases
for each row execute function public.guard_purchase_insert();

drop trigger if exists purchases_sync_request on public.purchases;
create trigger purchases_sync_request
after insert on public.purchases
for each row execute function public.sync_purchase_request_status();

drop trigger if exists purchases_prevent_mutation on public.purchases;
create trigger purchases_prevent_mutation
before update or delete on public.purchases
for each row execute function public.prevent_direct_purchase_mutation();

revoke all on function public.guard_purchase_insert() from public, anon, authenticated;
revoke all on function public.sync_purchase_request_status() from public, anon, authenticated;
revoke all on function public.prevent_direct_purchase_mutation() from public, anon, authenticated;
