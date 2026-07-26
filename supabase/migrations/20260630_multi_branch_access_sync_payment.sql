-- Sajia multi-branch access, direct owner sync, and payment provider expansion.
-- Run after the previous owner portal/payment migrations.

create extension if not exists pgcrypto;

alter table outlets add column if not exists owner_email text;
alter table outlets add column if not exists cloud_expiry timestamptz;
alter table outlets add column if not exists license_expiry timestamptz;
alter table outlets add column if not exists is_setup_done boolean default false;

create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists organization_members (
  organization_id uuid not null references organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table if not exists outlet_organizations (
  outlet_id text primary key references outlets(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists expenses (
  id text primary key,
  outlet_id text not null references outlets(id) on delete cascade,
  category text not null,
  description text,
  amount text not null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists organization_members_user_idx
  on organization_members(user_id);
create index if not exists outlet_organizations_organization_idx
  on outlet_organizations(organization_id);
create index if not exists expenses_outlet_occurred_idx
  on expenses(outlet_id, occurred_at desc);

create table if not exists product_variants (
  id text primary key,
  product_id text not null references products(id) on delete cascade,
  name text not null,
  options jsonb not null default '[]',
  is_required boolean default false,
  updated_at timestamptz default now()
);

create table if not exists plan_orders (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references outlets(id) on delete cascade,
  plan_code text not null check (plan_code in ('PRO_LIFETIME', 'CLOUD_MONTHLY')),
  status text not null check (status in ('PENDING', 'ACTIVE', 'EXPIRED', 'FAILED', 'CANCELLED')),
  amount bigint not null check (amount > 0),
  currency text not null default 'IDR',
  xendit_invoice_id text unique,
  xendit_external_id text unique not null,
  checkout_url text,
  paid_at timestamptz,
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists plan_orders_outlet_created_idx
  on plan_orders(outlet_id, created_at desc);

do $$
begin
  if exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'users_role_check'
      and table_schema = 'public'
      and table_name = 'users'
  ) then
    alter table users drop constraint users_role_check;
  end if;
end $$;

alter table users
  add constraint users_role_check
  check (role in ('owner', 'manager', 'cashier'));

create table if not exists user_outlet_accesses (
  id text primary key,
  user_id text not null references users(id) on delete cascade,
  outlet_id text not null references outlets(id) on delete cascade,
  created_at timestamptz not null default now()
);

create unique index if not exists user_outlet_accesses_unique_pair
  on user_outlet_accesses(user_id, outlet_id);
create index if not exists user_outlet_accesses_user_idx
  on user_outlet_accesses(user_id);
create index if not exists user_outlet_accesses_outlet_idx
  on user_outlet_accesses(outlet_id);

alter table plan_orders add column if not exists payment_provider text default 'MIDTRANS';
alter table plan_orders alter column payment_provider set default 'MIDTRANS';
alter table plan_orders add column if not exists provider_order_id text;
alter table plan_orders add column if not exists provider_reference_id text;
create unique index if not exists plan_orders_provider_order_idx
  on plan_orders(payment_provider, provider_order_id)
  where provider_order_id is not null;

create or replace function current_user_has_outlet(p_outlet_id text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from outlets outlet
    where outlet.id = p_outlet_id
      and lower(coalesce(outlet.owner_email, '')) =
          lower(coalesce(auth.jwt() ->> 'email', ''))
  )
  or exists (
    select 1
    from outlet_organizations outlet_org
    join organization_members member
      on member.organization_id = outlet_org.organization_id
    where outlet_org.outlet_id = p_outlet_id
      and member.user_id = auth.uid()
      and member.role in ('owner', 'admin')
  );
$$;

drop function if exists get_authenticated_owner_outlets();

create function get_authenticated_owner_outlets()
returns table (
  id text,
  name text,
  owner_email text,
  address text,
  phone text,
  tax_percent text,
  service_charge_percent text,
  receipt_header text,
  receipt_footer text,
  license_key text,
  license_expiry timestamptz,
  cloud_expiry timestamptz,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    outlet.id,
    outlet.name,
    outlet.owner_email,
    outlet.address,
    outlet.phone,
    outlet.tax_percent,
    outlet.service_charge_percent,
    outlet.receipt_header,
    outlet.receipt_footer,
    outlet.license_key,
    outlet.license_expiry,
    outlet.cloud_expiry,
    outlet.created_at
  from outlets outlet
  where auth.uid() is not null
    and (
      lower(coalesce(outlet.owner_email, '')) =
        lower(coalesce(auth.jwt() ->> 'email', ''))
      or current_user_has_outlet(outlet.id)
    )
  order by outlet.created_at asc;
$$;

drop function if exists get_owner_outlets();

create function get_owner_outlets()
returns table (
  id text,
  name text,
  address text,
  phone text,
  license_key text,
  cloud_expiry timestamptz,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select distinct
    outlet.id,
    outlet.name,
    outlet.address,
    outlet.phone,
    outlet.license_key,
    outlet.cloud_expiry,
    outlet.created_at
  from outlets outlet
  where current_user_has_outlet(outlet.id)
  order by outlet.created_at asc;
$$;

create or replace function ensure_owner_organization()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  owner_email_normalized text := lower(coalesce(auth.jwt() ->> 'email', ''));
  resolved_organization_id uuid;
  owned_outlet_count integer;
begin
  if current_user_id is null or owner_email_normalized = '' then
    raise exception 'AUTH_REQUIRED';
  end if;

  select count(*) into owned_outlet_count
  from outlets
  where lower(coalesce(owner_email, '')) = owner_email_normalized;

  if owned_outlet_count = 0 then
    raise exception 'OWNER_OUTLET_NOT_FOUND';
  end if;

  select organization_id into resolved_organization_id
  from organization_members
  where user_id = current_user_id and role in ('owner', 'admin')
  order by created_at asc
  limit 1;

  if resolved_organization_id is null then
    insert into organizations(name)
    values (split_part(owner_email_normalized, '@', 1) || ' Group')
    returning id into resolved_organization_id;

    insert into organization_members(organization_id, user_id, role)
    values (resolved_organization_id, current_user_id, 'owner');
  end if;

  insert into outlet_organizations(outlet_id, organization_id)
  select outlet.id, resolved_organization_id
  from outlets outlet
  where lower(coalesce(outlet.owner_email, '')) = owner_email_normalized
  on conflict (outlet_id) do nothing;

  return resolved_organization_id;
end;
$$;

create or replace function get_owner_dashboard(
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  dashboard jsonb;
begin
  if current_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  perform ensure_owner_organization();

  if not exists (
    select 1
    from organization_members member
    where member.user_id = current_user_id
      and member.role in ('owner', 'admin')
  ) then
    raise exception 'OWNER_ACCESS_REQUIRED';
  end if;

  with accessible_outlets as (
    select distinct outlet.id, outlet.name
    from outlets outlet
    join outlet_organizations outlet_org on outlet_org.outlet_id = outlet.id
    join organization_members member
      on member.organization_id = outlet_org.organization_id
    where member.user_id = current_user_id
      and member.role in ('owner', 'admin')
  ),
  paid_orders as (
    select order_row.id, order_row.outlet_id,
      coalesce(nullif(order_row.total, '')::numeric, 0) as total
    from orders order_row
    join accessible_outlets outlet on outlet.id = order_row.outlet_id
    where order_row.status = 'paid'
      and order_row.paid_at >= p_from
      and order_row.paid_at <= p_to
  ),
  revenue_by_outlet as (
    select outlet_id, coalesce(sum(total), 0) as revenue, count(*)::integer as transactions
    from paid_orders
    group by outlet_id
  ),
  cogs_by_outlet as (
    select paid.outlet_id,
      coalesce(sum(
        coalesce(nullif(product.cogs, '')::numeric, 0) *
        coalesce(nullif(item.quantity, '')::numeric, 0)
      ), 0) as cogs
    from paid_orders paid
    join order_items item on item.order_id = paid.id
    left join products product on product.id = item.product_id
    group by paid.outlet_id
  ),
  expenses_by_outlet as (
    select expense.outlet_id,
      coalesce(sum(coalesce(nullif(expense.amount, '')::numeric, 0)), 0) as expenses
    from expenses expense
    join accessible_outlets outlet on outlet.id = expense.outlet_id
    where expense.occurred_at >= p_from and expense.occurred_at <= p_to
    group by expense.outlet_id
  ),
  branches as (
    select outlet.id as outlet_id,
      outlet.name as outlet_name,
      coalesce(revenue.revenue, 0) as revenue,
      coalesce(cogs.cogs, 0) as cogs,
      coalesce(expense.expenses, 0) as expenses,
      coalesce(revenue.transactions, 0) as transactions
    from accessible_outlets outlet
    left join revenue_by_outlet revenue on revenue.outlet_id = outlet.id
    left join cogs_by_outlet cogs on cogs.outlet_id = outlet.id
    left join expenses_by_outlet expense on expense.outlet_id = outlet.id
  )
  select jsonb_build_object(
    'revenue', coalesce(sum(revenue), 0),
    'cogs', coalesce(sum(cogs), 0),
    'expenses', coalesce(sum(expenses), 0),
    'transactions', coalesce(sum(transactions), 0),
    'branches', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'outlet_id', outlet_id,
          'outlet_name', outlet_name,
          'revenue', revenue,
          'cogs', cogs,
          'expenses', expenses,
          'transactions', transactions,
          'net_profit', revenue - cogs - expenses
        ) order by revenue desc
      ),
      '[]'::jsonb
    )
  ) into dashboard
  from branches;

  return dashboard;
end;
$$;

alter table outlets enable row level security;
alter table users enable row level security;
alter table organizations enable row level security;
alter table organization_members enable row level security;
alter table outlet_organizations enable row level security;
alter table user_outlet_accesses enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table product_variants enable row level security;
alter table restaurant_tables enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table sessions enable row level security;
alter table expenses enable row level security;
alter table plan_orders enable row level security;

revoke all on table organizations, organization_members, outlet_organizations, plan_orders
from anon, authenticated;

grant select, insert, update, delete on
  outlets,
  users,
  user_outlet_accesses,
  categories,
  products,
  product_variants,
  restaurant_tables,
  orders,
  order_items,
  sessions,
  expenses
to authenticated;

drop policy if exists owner_outlet_scope on outlets;
create policy owner_outlet_scope on outlets
for all to authenticated
using (
  current_user_has_outlet(id)
  or lower(coalesce(owner_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
)
with check (
  lower(coalesce(owner_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or current_user_has_outlet(id)
);

drop policy if exists owner_scope_users on users;
create policy owner_scope_users on users
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_user_outlet_accesses on user_outlet_accesses;
create policy owner_scope_user_outlet_accesses on user_outlet_accesses
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_categories on categories;
create policy owner_scope_categories on categories
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_products on products;
create policy owner_scope_products on products
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_restaurant_tables on restaurant_tables;
create policy owner_scope_restaurant_tables on restaurant_tables
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_orders on orders;
create policy owner_scope_orders on orders
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_sessions on sessions;
create policy owner_scope_sessions on sessions
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_expenses on expenses;
create policy owner_scope_expenses on expenses
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_order_items on order_items;
create policy owner_scope_order_items on order_items
for all to authenticated
using (
  exists (
    select 1 from orders order_row
    where order_row.id = order_items.order_id
      and current_user_has_outlet(order_row.outlet_id)
  )
)
with check (
  exists (
    select 1 from orders order_row
    where order_row.id = order_items.order_id
      and current_user_has_outlet(order_row.outlet_id)
  )
);

drop policy if exists owner_scope_product_variants on product_variants;
create policy owner_scope_product_variants on product_variants
for all to authenticated
using (
  exists (
    select 1 from products product
    where product.id = product_variants.product_id
      and current_user_has_outlet(product.outlet_id)
  )
)
with check (
  exists (
    select 1 from products product
    where product.id = product_variants.product_id
      and current_user_has_outlet(product.outlet_id)
  )
);

revoke all on function current_user_has_outlet(text) from public;
revoke all on function get_authenticated_owner_outlets() from public;
revoke all on function get_owner_outlets() from public;
revoke all on function ensure_owner_organization() from public;
revoke all on function get_owner_dashboard(timestamptz, timestamptz) from public;
grant execute on function get_authenticated_owner_outlets() to authenticated;
grant execute on function get_owner_outlets() to authenticated;
grant execute on function ensure_owner_organization() to authenticated;
grant execute on function get_owner_dashboard(timestamptz, timestamptz) to authenticated;
