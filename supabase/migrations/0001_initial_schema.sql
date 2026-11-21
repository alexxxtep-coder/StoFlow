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
