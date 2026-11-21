-- STO.Flow 6.0 — complete schema for a new Supabase project
-- Run once in an empty project. Includes migrations 0001, 0002, 0003 and 0004.

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create type public.app_role as enum
  ('owner','admin','service_manager','service_advisor','mechanic','parts_manager','finance');
create type public.lead_status as enum
  ('new','contacted','booked','converted','lost','unreachable');
create type public.order_status as enum
  ('new','accepted','diagnostics','awaiting_approval','awaiting_parts','in_progress','quality_check','ready','completed','cancelled');
create type public.part_request_status as enum
  ('requested','searching','awaiting_approval','ordered','partially_received','received','cancelled');

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  currency char(3) not null default 'BYN',
  timezone text not null default 'Europe/Minsk',
  created_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null default 'service_advisor',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, user_id),
  unique (id, tenant_id)
);
create index memberships_user_active_idx on public.memberships(user_id, is_active);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  normalized_phone text not null,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (id, tenant_id)
);
create index customers_tenant_phone_idx on public.customers(tenant_id, normalized_phone);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null,
  make text,
  model text,
  model_year smallint check (model_year is null or model_year between 1886 and 2100),
  plate text,
  vin text,
  engine text,
  transmission text,
  vehicle_identity_source text not null default 'manual',
  identity_confidence text not null default 'unverified',
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (customer_id, tenant_id) references public.customers(id, tenant_id)
);
create index vehicles_tenant_vin_idx on public.vehicles(tenant_id, vin);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null,
  vehicle_id uuid,
  description text not null,
  source text not null default 'other' check (source in ('phone','messenger','website','walk_in','other')),
  status public.lead_status not null default 'new',
  owner_user_id uuid references auth.users(id),
  next_step text,
  next_step_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (id, tenant_id),
  foreign key (customer_id, tenant_id) references public.customers(id, tenant_id),
  foreign key (vehicle_id, tenant_id) references public.vehicles(id, tenant_id)
);
create index leads_tenant_status_created_idx on public.leads(tenant_id, status, created_at desc);

create table public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  category text,
  customer_price numeric(14,2) not null default 0 check (customer_price >= 0),
  direct_cost numeric(14,2) not null default 0 check (direct_cost >= 0),
  norm_minutes integer check (norm_minutes is null or norm_minutes > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, tenant_id)
);

create table public.resources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  resource_type text not null default 'bay',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, tenant_id)
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null,
  vehicle_id uuid,
  resource_id uuid,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'requested' check (status in ('requested','confirmed','arrived','cancelled','no_show')),
  notes text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  unique (id, tenant_id),
  foreign key (customer_id, tenant_id) references public.customers(id, tenant_id),
  foreign key (vehicle_id, tenant_id) references public.vehicles(id, tenant_id),
  foreign key (resource_id, tenant_id) references public.resources(id, tenant_id)
);
create index appointments_tenant_time_idx on public.appointments(tenant_id, starts_at, ends_at);
-- A resource cannot be occupied by overlapping active appointments, including concurrent requests.
alter table public.appointments add constraint appointments_no_resource_overlap
  exclude using gist (resource_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
  where (resource_id is not null and status in ('requested','confirmed','arrived'));

create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  order_number bigint generated by default as identity,
  customer_id uuid not null,
  vehicle_id uuid,
  appointment_id uuid,
  status public.order_status not null default 'new',
  complaint text,
  odometer integer check (odometer is null or odometer >= 0),
  planned_finish_at timestamptz,
  accepted_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (id, tenant_id),
  foreign key (customer_id, tenant_id) references public.customers(id, tenant_id),
  foreign key (vehicle_id, tenant_id) references public.vehicles(id, tenant_id),
  foreign key (appointment_id, tenant_id) references public.appointments(id, tenant_id)
);
create index work_orders_tenant_status_idx on public.work_orders(tenant_id, status, created_at desc);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null,
  from_status public.order_status,
  to_status public.order_status not null,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  note text,
  foreign key (work_order_id, tenant_id) references public.work_orders(id, tenant_id)
);
create index order_status_history_order_idx on public.order_status_history(tenant_id, work_order_id, changed_at desc);

create or replace function public.log_order_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status is distinct from new.status then
    insert into public.order_status_history(tenant_id,work_order_id,from_status,to_status,changed_by)
    values (new.tenant_id,new.id,old.status,new.status,auth.uid());
  end if;
  return new;
end; $$;
create trigger work_order_status_audit after update of status on public.work_orders
  for each row execute function public.log_order_status_change();

create or replace function public.enforce_order_status_transition()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.status is distinct from new.status then
    new.updated_at := now();
    if not (
      (old.status='new' and new.status in ('accepted','cancelled')) or
      (old.status='accepted' and new.status in ('diagnostics','awaiting_approval','awaiting_parts','in_progress','cancelled')) or
      (old.status='diagnostics' and new.status in ('awaiting_approval','awaiting_parts','in_progress','cancelled')) or
      (old.status='awaiting_approval' and new.status in ('awaiting_parts','in_progress','cancelled')) or
      (old.status='awaiting_parts' and new.status in ('in_progress','cancelled')) or
      (old.status='in_progress' and new.status in ('awaiting_approval','awaiting_parts','quality_check','cancelled')) or
      (old.status='quality_check' and new.status in ('in_progress','ready')) or
      (old.status='ready' and new.status in ('completed','in_progress'))
    ) then
      raise exception 'Invalid work order status transition: % -> %', old.status, new.status;
    end if;
  end if;
  return new;
end; $$;
create trigger work_order_status_guard before update of status on public.work_orders
  for each row execute function public.enforce_order_status_transition();

create table public.work_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null,
  line_type text not null check (line_type in ('labor','part','other')),
  description text not null,
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  norm_minutes integer,
  actual_minutes integer,
  assigned_user_id uuid references auth.users(id),
  line_status text not null default 'planned',
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (work_order_id, tenant_id) references public.work_orders(id, tenant_id)
);
create index order_lines_order_idx on public.work_order_lines(tenant_id, work_order_id);

-- Commercial amounts are separated from the mechanic-facing operation lines.
create table public.work_order_line_financials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_line_id uuid not null,
  customer_unit_price numeric(14,2) not null default 0 check (customer_unit_price >= 0),
  direct_unit_cost numeric(14,2) not null default 0 check (direct_unit_cost >= 0),
  updated_at timestamptz not null default now(),
  foreign key (work_order_line_id, tenant_id) references public.work_order_lines(id, tenant_id),
  unique (work_order_line_id)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  title text not null,
  description text,
  work_order_id uuid,
  lead_id uuid,
  assignee_user_id uuid references auth.users(id),
  status text not null default 'new' check (status in ('new','planned','in_progress','waiting','blocked','done','cancelled')),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  due_at timestamptz,
  blocked_reason text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  foreign key (work_order_id, tenant_id) references public.work_orders(id, tenant_id),
  foreign key (lead_id, tenant_id) references public.leads(id, tenant_id),
  unique (tenant_id, idempotency_key)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  integration_status text not null default 'manual_only' check (integration_status in ('manual_only','pending_credentials','connected','disabled')),
  created_at timestamptz not null default now(),
  unique (id, tenant_id)
);

create table public.part_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid,
  vehicle_id uuid,
  description text not null,
  oem_number text,
  manufacturer_sku text,
  cross_numbers text[] not null default '{}',
  preferred_brand text,
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  status public.part_request_status not null default 'requested',
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (id, tenant_id),
  foreign key (work_order_id, tenant_id) references public.work_orders(id, tenant_id),
  foreign key (vehicle_id, tenant_id) references public.vehicles(id, tenant_id)
);

create table public.supplier_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  part_request_id uuid not null,
  supplier_id uuid,
  brand text,
  sku text,
  title text not null,
  purchase_price numeric(14,2) check (purchase_price is null or purchase_price >= 0),
  currency char(3) not null default 'BYN',
  availability text not null default 'unknown' check (availability in ('unknown','in_stock','limited','backorder','out_of_stock')),
  available_quantity numeric(12,3),
  eta_at timestamptz,
  warranty_terms text,
  fitment_status text not null default 'unverified' check (fitment_status in ('confirmed','probable','not_fit','unverified')),
  source_type text not null default 'manual' check (source_type in ('manual','supplier_api','import')),
  source_reference text,
  observed_at timestamptz not null default now(),
  status text not null default 'received' check (status in ('received','checking','accepted','rejected','stale')),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (part_request_id, tenant_id) references public.part_requests(id, tenant_id),
  foreign key (supplier_id, tenant_id) references public.suppliers(id, tenant_id)
);
create index offers_request_idx on public.supplier_offers(tenant_id, part_request_id, observed_at desc);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid,
  part_request_id uuid,
  supplier_offer_id uuid,
  status text not null default 'draft' check (status in ('draft','approved','ordered','partially_received','received','cancelled')),
  ordered_at timestamptz,
  expected_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (supplier_id, tenant_id) references public.suppliers(id, tenant_id),
  foreign key (part_request_id, tenant_id) references public.part_requests(id, tenant_id),
  foreign key (supplier_offer_id, tenant_id) references public.supplier_offers(id, tenant_id),
  unique (tenant_id, supplier_offer_id)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  currency char(3) not null default 'BYN',
  payment_method text,
  reference text,
  paid_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (customer_id, tenant_id) references public.customers(id, tenant_id)
);

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  payment_id uuid not null,
  work_order_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  foreign key (payment_id, tenant_id) references public.payments(id, tenant_id),
  foreign key (work_order_id, tenant_id) references public.work_orders(id, tenant_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  category text not null,
  description text,
  amount numeric(14,2) not null check (amount >= 0),
  currency char(3) not null default 'BYN',
  expense_date date not null default current_date,
  work_order_id uuid,
  created_at timestamptz not null default now(),
  foreign key (work_order_id, tenant_id) references public.work_orders(id, tenant_id)
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_tenant_created_idx on public.audit_logs(tenant_id, created_at desc);

create or replace function public.audit_lead_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,after_data)
  values (new.tenant_id,auth.uid(),'lead.created','lead',new.id,jsonb_build_object('customer_id',new.customer_id,'vehicle_id',new.vehicle_id));
  return new;
end; $$;
create trigger leads_audit_insert after insert on public.leads
  for each row execute function public.audit_lead_insert();

create or replace function public.audit_work_order_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,after_data)
  values (new.tenant_id,auth.uid(),'work_order.created','work_order',new.id,jsonb_build_object('customer_id',new.customer_id,'vehicle_id',new.vehicle_id));
  insert into public.order_status_history(tenant_id,work_order_id,from_status,to_status,changed_by,note)
  values (new.tenant_id,new.id,null,new.status,auth.uid(),'Заказ создан');
  return new;
end; $$;
create trigger work_orders_audit_insert after insert on public.work_orders
  for each row execute function public.audit_work_order_insert();

-- RLS helper: derive tenant access from the authenticated user, never from browser-supplied role.
create or replace function public.is_tenant_member(target_tenant uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
    where m.tenant_id = target_tenant
      and m.user_id = auth.uid()
      and m.is_active = true
  );
$$;

create or replace function public.has_tenant_role(target_tenant uuid, allowed public.app_role[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
    where m.tenant_id = target_tenant
      and m.user_id = auth.uid()
      and m.is_active = true
      and m.role = any(allowed)
  );
$$;

create or replace function public.is_assigned_to_work_order(target_tenant uuid, target_order uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.work_order_lines l
    where l.tenant_id=target_tenant and l.work_order_id=target_order and l.assigned_user_id=auth.uid()
  ) or exists (
    select 1 from public.tasks t
    where t.tenant_id=target_tenant and t.work_order_id=target_order and t.assignee_user_id=auth.uid()
  );
$$;

-- Bootstrap an organization for the signed-in user. No client can assign itself into an existing tenant.
create or replace function public.create_workspace(p_name text)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare new_tenant uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(trim(p_name)) < 2 or char_length(trim(p_name)) > 120 then raise exception 'Invalid workspace name'; end if;
  insert into public.tenants(name) values (trim(p_name)) returning id into new_tenant;
  insert into public.memberships(tenant_id,user_id,role) values (new_tenant,auth.uid(),'owner');
  return new_tenant;
end;
$$;

-- Atomic vertical slice: customer + optional vehicle + lead. Tenant membership is checked in SQL.
create or replace function public.create_lead_with_context(
  p_tenant_id uuid, p_customer_name text, p_phone text,
  p_vehicle_make text default null, p_vehicle_model text default null,
  p_plate text default null, p_vin text default null,
  p_description text default null, p_source text default 'other'
)
returns uuid
language plpgsql security invoker
set search_path = public
as $$
declare customer_uuid uuid; vehicle_uuid uuid; lead_uuid uuid; normalized text;
begin
  if not public.is_tenant_member(p_tenant_id) then raise exception 'Tenant access denied'; end if;
  if char_length(trim(coalesce(p_customer_name,''))) < 2 then raise exception 'Customer name is required'; end if;
  if char_length(trim(coalesce(p_phone,''))) < 5 then raise exception 'Valid phone is required'; end if;
  if char_length(trim(coalesce(p_description,''))) < 3 then raise exception 'Description is required'; end if;
  normalized := regexp_replace(p_phone, '[^0-9+]', '', 'g');
  if char_length(normalized) < 5 then raise exception 'Phone must contain at least five digits'; end if;

  -- Serialize lookup/create for this tenant+phone to reduce duplicate customer records.
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':' || normalized, 0));
  select id into customer_uuid from public.customers
    where tenant_id = p_tenant_id and normalized_phone = normalized
    order by created_at asc limit 1 for update;
  if customer_uuid is null then
    insert into public.customers(tenant_id,name,normalized_phone,created_by)
    values (p_tenant_id,trim(p_customer_name),normalized,auth.uid())
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
      values (p_tenant_id,customer_uuid,nullif(trim(p_vehicle_make),''),nullif(trim(p_vehicle_model),''),
        nullif(trim(p_plate),''),nullif(upper(trim(p_vin)),''),'manual','unverified')
      returning id into vehicle_uuid;
    end if;
  end if;

  insert into public.leads(tenant_id,customer_id,vehicle_id,description,source,created_by,owner_user_id)
  values (p_tenant_id,customer_uuid,vehicle_uuid,trim(p_description),p_source,auth.uid(),auth.uid())
  returning id into lead_uuid;

  return lead_uuid;
end;
$$;

-- Convert an active lead into a work order without re-entering customer/vehicle data.
create or replace function public.create_work_order_from_lead(
  p_tenant_id uuid, p_lead_id uuid, p_complaint text default null, p_planned_finish_at timestamptz default null
)
returns uuid
language plpgsql security invoker
set search_path = public
as $$
declare source_lead public.leads%rowtype; new_order uuid;
begin
  if not public.has_tenant_role(p_tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]) then
    raise exception 'Permission denied';
  end if;
  select * into source_lead from public.leads
    where id=p_lead_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Lead not found'; end if;
  if source_lead.status in ('converted','lost') then raise exception 'Lead is already closed'; end if;

  insert into public.work_orders(tenant_id,customer_id,vehicle_id,complaint,planned_finish_at,created_by)
  values (p_tenant_id,source_lead.customer_id,source_lead.vehicle_id,
    coalesce(nullif(trim(p_complaint),''),source_lead.description),p_planned_finish_at,auth.uid())
  returning id into new_order;

  update public.leads set status='converted', updated_at=now() where id=p_lead_id and tenant_id=p_tenant_id;
  return new_order;
end;
$$;

-- Manual supplier offer: no supplier API is implied by this operation.
create or replace function public.add_manual_supplier_offer(
  p_tenant_id uuid, p_part_request_id uuid, p_supplier_name text, p_title text,
  p_brand text default null, p_sku text default null, p_purchase_price numeric default null,
  p_currency text default 'BYN', p_availability text default 'unknown',
  p_eta_at timestamptz default null, p_fitment_status text default 'unverified'
)
returns uuid
language plpgsql security invoker
set search_path = public
as $$
declare supplier_uuid uuid; offer_uuid uuid;
begin
  if not public.has_tenant_role(p_tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]) then
    raise exception 'Permission denied';
  end if;
  if not exists(select 1 from public.part_requests where id=p_part_request_id and tenant_id=p_tenant_id) then
    raise exception 'Part request not found';
  end if;
  if char_length(trim(coalesce(p_supplier_name,''))) < 2 or char_length(trim(coalesce(p_title,''))) < 2 then
    raise exception 'Supplier and offer title are required';
  end if;
  if char_length(coalesce(p_currency,'BYN')) <> 3 then raise exception 'Currency must be a three-letter code'; end if;
  select id into supplier_uuid from public.suppliers
    where tenant_id=p_tenant_id and lower(name)=lower(trim(p_supplier_name)) limit 1;
  if supplier_uuid is null then
    insert into public.suppliers(tenant_id,name,integration_status)
    values (p_tenant_id,trim(p_supplier_name),'manual_only') returning id into supplier_uuid;
  end if;
  insert into public.supplier_offers(
    tenant_id,part_request_id,supplier_id,brand,sku,title,purchase_price,currency,
    availability,eta_at,fitment_status,source_type,source_reference,observed_at,status
  ) values (
    p_tenant_id,p_part_request_id,supplier_uuid,nullif(trim(p_brand),''),nullif(trim(p_sku),''),trim(p_title),
    p_purchase_price,coalesce(p_currency,'BYN'),p_availability,p_eta_at,p_fitment_status,'manual','manual entry',now(),'received'
  ) returning id into offer_uuid;
  return offer_uuid;
end;
$$;

-- Accept a manually entered offer and create a purchase record in one transaction.
create or replace function public.create_purchase_from_offer(p_tenant_id uuid, p_offer_id uuid)
returns uuid
language plpgsql security invoker
set search_path = public
as $$
declare chosen_offer public.supplier_offers%rowtype; new_purchase uuid;
begin
  if not public.has_tenant_role(p_tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]) then
    raise exception 'Permission denied';
  end if;
  select * into chosen_offer from public.supplier_offers
    where id=p_offer_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Offer not found'; end if;
  if chosen_offer.status in ('rejected','stale') then raise exception 'Offer cannot be purchased'; end if;
  insert into public.purchases(tenant_id,supplier_id,part_request_id,supplier_offer_id,status,ordered_at,expected_at)
  values (p_tenant_id,chosen_offer.supplier_id,chosen_offer.part_request_id,chosen_offer.id,'ordered',now(),chosen_offer.eta_at)
  on conflict (tenant_id,supplier_offer_id) do nothing
  returning id into new_purchase;
  if new_purchase is null then
    select id into new_purchase from public.purchases where tenant_id=p_tenant_id and supplier_offer_id=chosen_offer.id;
  end if;
  update public.supplier_offers set status='accepted' where id=p_offer_id and tenant_id=p_tenant_id;
  update public.part_requests set status='ordered' where id=chosen_offer.part_request_id and tenant_id=p_tenant_id;
  return new_purchase;
end;
$$;

-- RLS policies. Every tenant table is scoped by membership.
do $$
declare t text;
begin
  foreach t in array array[
    'resources'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy tenant_select on public.%I for select using (public.is_tenant_member(tenant_id))', t);
    execute format('create policy tenant_insert on public.%I for insert with check (public.is_tenant_member(tenant_id))', t);
    execute format('create policy tenant_update on public.%I for update using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id))', t);
    execute format('create policy tenant_delete on public.%I for delete using (public.has_tenant_role(tenant_id, array[''owner'',''admin'']::public.app_role[]))', t);
  end loop;
end $$;

alter table public.appointments enable row level security;
create policy appointments_select on public.appointments for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
  or exists (select 1 from public.work_orders wo where wo.tenant_id=appointments.tenant_id and wo.appointment_id=appointments.id
    and public.is_assigned_to_work_order(wo.tenant_id,wo.id))
);
create policy appointments_insert on public.appointments for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy appointments_update on public.appointments for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
) with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]));
create policy appointments_delete on public.appointments for delete using (public.has_tenant_role(tenant_id,array['owner','admin']::public.app_role[]));

-- CRM visibility: mechanics only see customer/vehicle records attached to their assigned work.
alter table public.customers enable row level security;
create policy customers_select on public.customers for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
  or exists (select 1 from public.work_orders wo where wo.tenant_id=customers.tenant_id and wo.customer_id=customers.id
    and public.is_assigned_to_work_order(wo.tenant_id,wo.id))
);
create policy customers_insert on public.customers for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy customers_update on public.customers for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
) with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]));
create policy customers_delete on public.customers for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));

alter table public.vehicles enable row level security;
create policy vehicles_select on public.vehicles for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
  or exists (select 1 from public.work_orders wo where wo.tenant_id=vehicles.tenant_id and wo.vehicle_id=vehicles.id
    and public.is_assigned_to_work_order(wo.tenant_id,wo.id))
);
create policy vehicles_insert on public.vehicles for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy vehicles_update on public.vehicles for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
) with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]));
create policy vehicles_delete on public.vehicles for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));

alter table public.leads enable row level security;
create policy leads_select on public.leads for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy leads_insert on public.leads for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy leads_update on public.leads for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
) with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]));
create policy leads_delete on public.leads for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));

alter table public.service_catalog enable row level security;
create policy service_catalog_select on public.service_catalog for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
);
create policy service_catalog_insert on public.service_catalog for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[])
);
create policy service_catalog_update on public.service_catalog for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[])
) with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[]));
create policy service_catalog_delete on public.service_catalog for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));

alter table public.work_orders enable row level security;
create policy work_orders_select on public.work_orders for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
  or (public.has_tenant_role(tenant_id, array['mechanic']::public.app_role[]) and public.is_assigned_to_work_order(tenant_id,id))
);
create policy work_orders_insert on public.work_orders for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy work_orders_update on public.work_orders for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
) with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]));
create policy work_orders_delete on public.work_orders for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));

alter table public.work_order_lines enable row level security;
create policy work_order_lines_select on public.work_order_lines for select using (
  exists (select 1 from public.work_orders wo where wo.id=work_order_lines.work_order_id and wo.tenant_id=work_order_lines.tenant_id)
);
create policy work_order_lines_insert on public.work_order_lines for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy work_order_lines_update on public.work_order_lines for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
  or (assigned_user_id=auth.uid() and public.has_tenant_role(tenant_id,array['mechanic']::public.app_role[]))
) with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
  or (assigned_user_id=auth.uid() and public.has_tenant_role(tenant_id,array['mechanic']::public.app_role[]))
);
create policy work_order_lines_delete on public.work_order_lines for delete using (public.has_tenant_role(tenant_id,array['owner','admin','service_manager']::public.app_role[]));

alter table public.tasks enable row level security;
create policy tasks_select on public.tasks for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
  or assignee_user_id=auth.uid()
);
create policy tasks_insert on public.tasks for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
);
create policy tasks_update on public.tasks for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
  or assignee_user_id=auth.uid()
) with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[])
  or assignee_user_id=auth.uid()
);
create policy tasks_delete on public.tasks for delete using (public.has_tenant_role(tenant_id,array['owner','admin','service_manager']::public.app_role[]));

alter table public.part_requests enable row level security;
create policy part_requests_select on public.part_requests for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
  or (work_order_id is not null and public.is_assigned_to_work_order(tenant_id,work_order_id))
);
create policy part_requests_insert on public.part_requests for insert with check (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','mechanic']::public.app_role[])
);
create policy part_requests_update on public.part_requests for update using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[])
) with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]));
create policy part_requests_delete on public.part_requests for delete using (public.has_tenant_role(tenant_id,array['owner','admin']::public.app_role[]));

-- Membership management is privileged: ordinary members must not grant themselves roles.
alter table public.memberships enable row level security;
create policy memberships_select on public.memberships for select
  using (user_id = auth.uid() or public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));
create policy memberships_insert on public.memberships for insert
  with check (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));
create policy memberships_update on public.memberships for update
  using (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));
create policy memberships_delete on public.memberships for delete
  using (public.has_tenant_role(tenant_id, array['owner','admin']::public.app_role[]));

-- Commercial, procurement and financial data is restricted by role, not merely by tenant membership.
alter table public.work_order_line_financials enable row level security;
create policy order_line_financials_select on public.work_order_line_financials for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[]));
create policy order_line_financials_insert on public.work_order_line_financials for insert
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]));
create policy order_line_financials_update on public.work_order_line_financials for update
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]));

alter table public.suppliers enable row level security;
create policy suppliers_select on public.suppliers for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager']::public.app_role[]));
create policy suppliers_write on public.suppliers for all
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]));

alter table public.supplier_offers enable row level security;
create policy supplier_offers_select on public.supplier_offers for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[]));
create policy supplier_offers_write on public.supplier_offers for all
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]));

alter table public.purchases enable row level security;
create policy purchases_select on public.purchases for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager','finance']::public.app_role[]));
create policy purchases_write on public.purchases for all
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','parts_manager']::public.app_role[]));

alter table public.payments enable row level security;
create policy payments_select on public.payments for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]));
create policy payments_insert on public.payments for insert
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]));

alter table public.payment_allocations enable row level security;
create policy payment_allocations_select on public.payment_allocations for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]));
create policy payment_allocations_insert on public.payment_allocations for insert
  with check (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]));

alter table public.expenses enable row level security;
create policy expenses_select on public.expenses for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager','finance']::public.app_role[]));
create policy expenses_insert on public.expenses for insert
  with check (public.has_tenant_role(tenant_id, array['owner','admin','finance']::public.app_role[]));

-- Status history is append-only; members may read their tenant's history and the trigger records transitions.
alter table public.order_status_history enable row level security;
create policy order_history_select on public.order_status_history for select using (
  public.has_tenant_role(tenant_id, array['owner','admin','service_manager','service_advisor','parts_manager','finance']::public.app_role[])
  or public.is_assigned_to_work_order(tenant_id,work_order_id)
);
-- Only the SECURITY DEFINER status trigger can append history rows.
revoke insert, update, delete on public.order_status_history from anon, authenticated;
grant select on public.order_status_history to authenticated;

-- Audit records are append-only. Direct writes are intentionally unavailable.
alter table public.audit_logs enable row level security;
create policy audit_select on public.audit_logs for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','service_manager']::public.app_role[]));
revoke insert, update, delete on public.audit_logs from anon, authenticated;
grant select on public.audit_logs to authenticated;

alter table public.tenants enable row level security;
create policy tenant_read on public.tenants for select using (public.is_tenant_member(id));
create policy tenant_update on public.tenants for update using (public.has_tenant_role(id, array['owner','admin']::public.app_role[]))
with check (public.has_tenant_role(id, array['owner','admin']::public.app_role[]));

revoke all on function public.create_workspace(text) from public, anon;
grant execute on function public.create_workspace(text) to authenticated;
revoke all on function public.create_lead_with_context(uuid,text,text,text,text,text,text,text,text) from public, anon;
revoke all on function public.create_work_order_from_lead(uuid,uuid,text,timestamptz) from public, anon;
revoke all on function public.add_manual_supplier_offer(uuid,uuid,text,text,text,text,numeric,text,text,timestamptz,text) from public, anon;
revoke all on function public.create_purchase_from_offer(uuid,uuid) from public, anon;
grant execute on function public.create_lead_with_context(uuid,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.create_work_order_from_lead(uuid,uuid,text,timestamptz) to authenticated;
grant execute on function public.add_manual_supplier_offer(uuid,uuid,text,text,text,text,numeric,text,text,timestamptz,text) to authenticated;
grant execute on function public.create_purchase_from_offer(uuid,uuid) to authenticated;
grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_role(uuid,public.app_role[]) to authenticated;


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


-- STO.Flow 6.0 — financial integrity hardening.
-- Apply after 0001_initial_schema.sql and 0002_transactional_operations.sql.
-- No existing financial rows are changed by this migration.

-- A user without a tenant switcher may create only one active workspace.
-- Enforce this in the privileged RPC, not only in the onboarding page.
create or replace function public.create_workspace(p_name text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare new_tenant uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(trim(p_name)) < 2 or char_length(trim(p_name)) > 120 then raise exception 'Invalid workspace name'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  if exists (select 1 from public.memberships m where m.user_id = auth.uid() and m.is_active) then
    raise exception 'User already belongs to an active workspace';
  end if;
  insert into public.tenants(name) values (trim(p_name)) returning id into new_tenant;
  insert into public.memberships(tenant_id,user_id,role) values (new_tenant,auth.uid(),'owner');
  return new_tenant;
end;
$$;
revoke all on function public.create_workspace(text) from public, anon;
grant execute on function public.create_workspace(text) to authenticated;

-- Revalidate order-line writes at the database boundary: numeric columns must
-- not silently round excess precision, and closed orders are immutable.
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
set search_path = public, pg_temp
as $$
declare
  new_line uuid;
  parent_status public.order_status;
begin
  if auth.uid() is null or not public.has_tenant_role(
    p_tenant_id, array['owner','admin','service_manager','service_advisor']::public.app_role[]
  ) then
    raise exception 'Permission denied';
  end if;
  if p_line_type not in ('labor','part','other') then raise exception 'Invalid line type'; end if;
  if nullif(trim(coalesce(p_description,'')),'') is null or char_length(trim(p_description)) > 240 then raise exception 'Invalid description'; end if;
  if p_quantity is null or p_quantity <= 0 or p_quantity <> round(p_quantity,3) then raise exception 'Quantity must be positive with at most three decimal places'; end if;
  if p_customer_unit_price is null or p_customer_unit_price < 0 or p_customer_unit_price > 100000000 or p_customer_unit_price <> round(p_customer_unit_price,2) then raise exception 'Invalid customer price'; end if;
  if p_direct_unit_cost is null or p_direct_unit_cost < 0 or p_direct_unit_cost > 100000000 or p_direct_unit_cost <> round(p_direct_unit_cost,2) then raise exception 'Invalid direct cost'; end if;
  select status into parent_status from public.work_orders
  where id=p_work_order_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Work order not found'; end if;
  if parent_status in ('completed','cancelled') then raise exception 'Cannot add lines to a completed or cancelled work order'; end if;

  insert into public.work_order_lines(tenant_id,work_order_id,line_type,description,quantity)
  values(p_tenant_id,p_work_order_id,p_line_type,trim(p_description),p_quantity)
  returning id into new_line;
  insert into public.work_order_line_financials(tenant_id,work_order_line_id,customer_unit_price,direct_unit_cost)
  values(p_tenant_id,new_line,p_customer_unit_price,p_direct_unit_cost);
  return new_line;
end;
$$;
revoke all on function public.add_work_order_line_with_financials(uuid,uuid,text,text,numeric,numeric,numeric) from public, anon;
grant execute on function public.add_work_order_line_with_financials(uuid,uuid,text,text,numeric,numeric,numeric) to authenticated;

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
set search_path = public, pg_temp
as $$
declare
  new_payment uuid;
  order_customer uuid;
  tenant_currency text;
  order_total numeric(14,2);
  already_allocated numeric(14,2);
  outstanding numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_tenant_role(
    p_tenant_id,
    array['owner','admin','service_manager','service_advisor','finance']::public.app_role[]
  ) then
    raise exception 'Permission denied';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount > 100000000 or p_amount <> round(p_amount, 2) then
    raise exception 'Payment amount must be positive and have at most two decimal places';
  end if;

  if p_payment_method is null or p_payment_method not in ('cash','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;

  select upper(trim(t.currency))
    into tenant_currency
  from public.tenants t
  where t.id = p_tenant_id;

  if tenant_currency is null then
    raise exception 'Workspace not found';
  end if;
  if upper(trim(coalesce(p_currency,''))) <> tenant_currency then
    raise exception 'Payment currency does not match workspace currency';
  end if;

  if char_length(coalesce(p_reference,'')) > 160 then
    raise exception 'Payment reference is too long';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id and c.tenant_id = p_tenant_id
  ) then
    raise exception 'Customer not found in this workspace';
  end if;

  if p_work_order_id is not null then
    -- Serialize all allocations for the same order, including concurrent requests.
    select wo.customer_id
      into order_customer
    from public.work_orders wo
    where wo.id = p_work_order_id and wo.tenant_id = p_tenant_id
    for update;

    if not found then
      raise exception 'Work order not found in this workspace';
    end if;
    if order_customer <> p_customer_id then
      raise exception 'Work order does not belong to customer';
    end if;

    if exists (
      select 1
      from public.work_order_lines l
      left join public.work_order_line_financials f
        on f.work_order_line_id = l.id and f.tenant_id = l.tenant_id
      where l.tenant_id = p_tenant_id and l.work_order_id = p_work_order_id
        and f.work_order_line_id is null
    ) then
      raise exception 'Work order has lines with missing financial prices';
    end if;

    select coalesce(sum(l.quantity * coalesce(f.customer_unit_price, 0)), 0)::numeric(14,2)
      into order_total
    from public.work_order_lines l
    left join public.work_order_line_financials f
      on f.work_order_line_id = l.id and f.tenant_id = l.tenant_id
    where l.tenant_id = p_tenant_id and l.work_order_id = p_work_order_id;

    select coalesce(sum(pa.amount), 0)::numeric(14,2)
      into already_allocated
    from public.payment_allocations pa
    where pa.tenant_id = p_tenant_id and pa.work_order_id = p_work_order_id;

    outstanding := order_total - already_allocated;
    if outstanding <= 0 then
      raise exception 'Work order has no outstanding balance';
    end if;
    if p_amount > outstanding then
      raise exception 'Payment exceeds outstanding work order balance (% remaining)', outstanding;
    end if;
  end if;

  insert into public.payments(
    tenant_id, customer_id, amount, currency, payment_method, reference, created_by
  ) values (
    p_tenant_id, p_customer_id, p_amount, tenant_currency, p_payment_method,
    nullif(trim(coalesce(p_reference,'')),''), auth.uid()
  ) returning id into new_payment;

  if p_work_order_id is not null then
    insert into public.payment_allocations(tenant_id, payment_id, work_order_id, amount)
    values (p_tenant_id, new_payment, p_work_order_id, p_amount);
  end if;

  return new_payment;
end;
$$;

revoke all on function public.create_payment_with_allocation(uuid,uuid,numeric,text,text,text,uuid) from public, anon;
grant execute on function public.create_payment_with_allocation(uuid,uuid,numeric,text,text,text,uuid) to authenticated;

-- Database-level guard against allocation totals exceeding the payment itself.
create or replace function public.enforce_payment_allocation_limit()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  payment_amount numeric(14,2);
  payment_customer uuid;
  order_customer uuid;
  allocated_before numeric(14,2);
  order_total numeric(14,2);
  order_allocated numeric(14,2);
begin
  -- Lock the order first, matching create_payment_with_allocation and line-edit
  -- triggers below. This consistent lock order avoids payment/order deadlocks.
  select wo.customer_id into order_customer
  from public.work_orders wo
  where wo.id = new.work_order_id and wo.tenant_id = new.tenant_id
  for update;
  if not found then raise exception 'Work order not found'; end if;

  select p.amount, p.customer_id into payment_amount, payment_customer
  from public.payments p
  where p.id = new.payment_id and p.tenant_id = new.tenant_id
  for update;
  if not found then raise exception 'Payment not found'; end if;
  if payment_customer <> order_customer then
    raise exception 'Payment customer does not match work order customer';
  end if;

  select coalesce(sum(pa.amount),0)::numeric(14,2) into allocated_before
  from public.payment_allocations pa
  where pa.payment_id = new.payment_id and pa.tenant_id = new.tenant_id
    and (tg_op <> 'UPDATE' or pa.id <> new.id);
  if allocated_before + new.amount > payment_amount then
    raise exception 'Allocated amount exceeds payment amount';
  end if;

  if exists (
    select 1
    from public.work_order_lines l
    left join public.work_order_line_financials f
      on f.work_order_line_id=l.id and f.tenant_id=l.tenant_id
    where l.tenant_id=new.tenant_id and l.work_order_id=new.work_order_id
      and f.work_order_line_id is null
  ) then
    raise exception 'Work order has lines with missing financial prices';
  end if;

  select coalesce(sum(l.quantity * coalesce(f.customer_unit_price,0)),0)::numeric(14,2)
    into order_total
  from public.work_order_lines l
  left join public.work_order_line_financials f
    on f.work_order_line_id=l.id and f.tenant_id=l.tenant_id
  where l.tenant_id=new.tenant_id and l.work_order_id=new.work_order_id;

  select coalesce(sum(pa.amount),0)::numeric(14,2) into order_allocated
  from public.payment_allocations pa
  where pa.work_order_id=new.work_order_id and pa.tenant_id=new.tenant_id
    and (tg_op <> 'UPDATE' or pa.id <> new.id);
  if order_allocated + new.amount > order_total then
    raise exception 'Allocations exceed work order total';
  end if;
  return new;
end;
$$;

drop trigger if exists payment_allocation_limit_guard on public.payment_allocations;
create trigger payment_allocation_limit_guard
before insert or update of amount, payment_id, tenant_id, work_order_id
on public.payment_allocations
for each row execute function public.enforce_payment_allocation_limit();

revoke all on function public.enforce_payment_allocation_limit() from public, anon, authenticated;


-- Serialize every direct line/price mutation against payment allocation. The
-- application RPC already takes this lock; these triggers close the direct-table
-- write path as well, so exposed Supabase tables cannot bypass the invariant.
create or replace function public.lock_work_order_for_line_change()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  target_order uuid;
  target_tenant uuid;
  parent_status public.order_status;
begin
  if tg_op = 'UPDATE' and (new.work_order_id is distinct from old.work_order_id or new.tenant_id is distinct from old.tenant_id) then
    raise exception 'A work-order line cannot be moved between orders or tenants';
  end if;
  if tg_op = 'DELETE' then
    target_order := old.work_order_id;
    target_tenant := old.tenant_id;
  else
    target_order := new.work_order_id;
    target_tenant := new.tenant_id;
  end if;
  select status into parent_status from public.work_orders
  where id = target_order and tenant_id = target_tenant
  for update;
  if not found then raise exception 'Work order not found'; end if;
  if parent_status in ('completed','cancelled') then
    raise exception 'Cannot change lines of a completed or cancelled work order';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists work_order_lines_lock_parent on public.work_order_lines;
create trigger work_order_lines_lock_parent
before insert or update or delete on public.work_order_lines
for each row execute function public.lock_work_order_for_line_change();

create or replace function public.lock_work_order_for_financial_line_change()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  target_order uuid;
  parent_status public.order_status;
begin
  if tg_op = 'UPDATE' and (new.work_order_line_id is distinct from old.work_order_line_id or new.tenant_id is distinct from old.tenant_id) then
    raise exception 'Financial data cannot be moved between work-order lines or tenants';
  end if;
  select l.work_order_id into target_order
  from public.work_order_lines l
  where l.id = new.work_order_line_id and l.tenant_id = new.tenant_id;
  if not found then raise exception 'Work order line not found'; end if;
  select status into parent_status from public.work_orders
  where id = target_order and tenant_id = new.tenant_id
  for update;
  if not found then raise exception 'Work order not found'; end if;
  if parent_status in ('completed','cancelled') then
    raise exception 'Cannot change financial lines of a completed or cancelled work order';
  end if;
  return new;
end;
$$;

drop trigger if exists work_order_line_financials_lock_parent on public.work_order_line_financials;
create trigger work_order_line_financials_lock_parent
before insert or update on public.work_order_line_financials
for each row execute function public.lock_work_order_for_financial_line_change();

revoke all on function public.lock_work_order_for_line_change() from public, anon, authenticated;
revoke all on function public.lock_work_order_for_financial_line_change() from public, anon, authenticated;

-- A later price/quantity reduction must not make already allocated payments
-- exceed the order's revised billed total. The BEFORE triggers above serialize
-- these checks with payment allocation on the same work-order row.
create or replace function public.assert_order_allocations_within_total()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  target_order uuid;
  target_tenant uuid;
  billed_total numeric(14,2);
  allocated_total numeric(14,2);
begin
  if tg_table_name = 'work_order_lines' then
    target_order := new.work_order_id;
    target_tenant := new.tenant_id;
  else
    select l.work_order_id into target_order
    from public.work_order_lines l
    where l.id = new.work_order_line_id and l.tenant_id = new.tenant_id;
    target_tenant := new.tenant_id;
  end if;

  select coalesce(sum(l.quantity * f.customer_unit_price), 0)::numeric(14,2)
    into billed_total
  from public.work_order_lines l
  join public.work_order_line_financials f
    on f.work_order_line_id = l.id and f.tenant_id = l.tenant_id
  where l.tenant_id = target_tenant and l.work_order_id = target_order;

  select coalesce(sum(pa.amount), 0)::numeric(14,2)
    into allocated_total
  from public.payment_allocations pa
  where pa.tenant_id = target_tenant and pa.work_order_id = target_order;

  if allocated_total > billed_total then
    raise exception 'Updated work-order total cannot be lower than allocated payments';
  end if;
  return null;
end;
$$;

drop trigger if exists work_order_lines_allocation_balance_guard on public.work_order_lines;
create trigger work_order_lines_allocation_balance_guard
after update of quantity on public.work_order_lines
for each row execute function public.assert_order_allocations_within_total();

drop trigger if exists work_order_line_financials_allocation_balance_guard on public.work_order_line_financials;
create trigger work_order_line_financials_allocation_balance_guard
after insert or update of customer_unit_price on public.work_order_line_financials
for each row execute function public.assert_order_allocations_within_total();
revoke all on function public.assert_order_allocations_within_total() from public, anon, authenticated;

-- Tasks may remain visible after handover, but new tasks cannot be attached to a
-- completed/cancelled order. Lock the parent to serialize against status changes.
create or replace function public.guard_task_work_order_status()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare parent_status public.order_status;
begin
  if new.work_order_id is null then return new; end if;
  select status into parent_status from public.work_orders
  where id = new.work_order_id and tenant_id = new.tenant_id
  for update;
  if not found then raise exception 'Work order not found'; end if;
  if parent_status in ('completed','cancelled') then
    raise exception 'Cannot attach a task to a completed or cancelled work order';
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_work_order_status_guard on public.tasks;
create trigger tasks_work_order_status_guard
before insert or update of work_order_id, tenant_id on public.tasks
for each row execute function public.guard_task_work_order_status();
revoke all on function public.guard_task_work_order_status() from public, anon, authenticated;

create or replace function public.guard_part_request_work_order_status()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare parent_status public.order_status;
begin
  if new.work_order_id is null then return new; end if;
  select status into parent_status from public.work_orders
  where id = new.work_order_id and tenant_id = new.tenant_id
  for update;
  if not found then raise exception 'Work order not found'; end if;
  if parent_status in ('completed','cancelled') then
    raise exception 'Cannot create a part request for a completed or cancelled work order';
  end if;
  return new;
end;
$$;

drop trigger if exists part_requests_work_order_status_guard on public.part_requests;
create trigger part_requests_work_order_status_guard
before insert or update of work_order_id, tenant_id on public.part_requests
for each row execute function public.guard_part_request_work_order_status();
revoke all on function public.guard_part_request_work_order_status() from public, anon, authenticated;


-- Protect direct authenticated inserts into the exposed payments table too.
create or replace function public.validate_payment_record()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  expected_currency text;
begin
  if new.amount <= 0 or new.amount > 100000000 or new.amount <> round(new.amount,2) then
    raise exception 'Invalid payment amount';
  end if;
  if new.payment_method is null or new.payment_method not in ('cash','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;
  if char_length(coalesce(new.reference,'')) > 160 then
    raise exception 'Payment reference is too long';
  end if;
  select upper(trim(t.currency)) into expected_currency
  from public.tenants t where t.id = new.tenant_id;
  if expected_currency is null or upper(trim(new.currency)) <> expected_currency then
    raise exception 'Payment currency does not match workspace currency';
  end if;
  return new;
end;
$$;

drop trigger if exists payments_validate_record on public.payments;
create trigger payments_validate_record
before insert or update of amount, currency, payment_method, reference
on public.payments
for each row execute function public.validate_payment_record();

-- Recover completion timestamps for older completed orders where status history exists.
update public.work_orders wo
set completed_at = (
  select max(h.changed_at)
  from public.order_status_history h
  where h.tenant_id = wo.tenant_id
    and h.work_order_id = wo.id
    and h.to_status = 'completed'
)
where wo.status = 'completed'
  and wo.completed_at is null
  and exists (
    select 1 from public.order_status_history h
    where h.tenant_id = wo.tenant_id
      and h.work_order_id = wo.id
      and h.to_status = 'completed'
  );

-- The completion timestamp is a database invariant, not a UI-only side effect.
create or replace function public.enforce_order_status_transition()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.status is distinct from new.status then
    new.updated_at := now();
    if not (
      (old.status='new' and new.status in ('accepted','cancelled')) or
      (old.status='accepted' and new.status in ('diagnostics','awaiting_approval','awaiting_parts','in_progress','cancelled')) or
      (old.status='diagnostics' and new.status in ('awaiting_approval','awaiting_parts','in_progress','cancelled')) or
      (old.status='awaiting_approval' and new.status in ('awaiting_parts','in_progress','cancelled')) or
      (old.status='awaiting_parts' and new.status in ('in_progress','cancelled')) or
      (old.status='in_progress' and new.status in ('awaiting_approval','awaiting_parts','quality_check','cancelled')) or
      (old.status='quality_check' and new.status in ('in_progress','ready')) or
      (old.status='ready' and new.status in ('completed','in_progress'))
    ) then
      raise exception 'Invalid work order status transition: % -> %', old.status, new.status;
    end if;
    if new.status = 'completed' then
      new.completed_at := coalesce(new.completed_at, now());
    elsif new.status <> 'completed' then
      new.completed_at := null;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.validate_payment_record() from public, anon, authenticated;

-- Harden existing SECURITY DEFINER routines against search_path shadowing.
alter function public.audit_lead_insert() set search_path = pg_catalog, public, pg_temp;
alter function public.audit_work_order_insert() set search_path = pg_catalog, public, pg_temp;
alter function public.log_order_status_change() set search_path = pg_catalog, public, pg_temp;
alter function public.is_tenant_member(uuid) set search_path = pg_catalog, public, pg_temp;
alter function public.has_tenant_role(uuid, public.app_role[]) set search_path = pg_catalog, public, pg_temp;
alter function public.is_assigned_to_work_order(uuid, uuid) set search_path = pg_catalog, public, pg_temp;
alter function public.create_workspace(text) set search_path = pg_catalog, public, pg_temp;

revoke all on function public.audit_lead_insert() from public, anon, authenticated;
revoke all on function public.audit_work_order_insert() from public, anon, authenticated;
revoke all on function public.log_order_status_change() from public, anon, authenticated;
revoke all on function public.is_tenant_member(uuid) from public, anon;
revoke all on function public.has_tenant_role(uuid, public.app_role[]) from public, anon;
revoke all on function public.is_assigned_to_work_order(uuid, uuid) from public, anon;
revoke all on function public.create_workspace(text) from public, anon;
grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_role(uuid, public.app_role[]) to authenticated;
grant execute on function public.is_assigned_to_work_order(uuid, uuid) to authenticated;
grant execute on function public.create_workspace(text) to authenticated;


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
