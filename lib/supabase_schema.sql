-- =============================================
-- POS F&B — Supabase Schema
-- Jalankan di Supabase SQL Editor
-- =============================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ─────────────────────────────────────────────
-- OUTLETS
-- ─────────────────────────────────────────────
create table outlets (
  id text primary key,
  name text not null,
  owner_email text,
  address text,
  phone text,
  tax_percent text default '0',
  service_charge_percent text default '0',
  receipt_header text,
  receipt_footer text,
  license_key text not null,
  license_expiry timestamptz,
  cloud_expiry timestamptz,
  is_setup_done boolean default false,
  created_at timestamptz default now()
);

-- -------------------------------------------------------------
-- LICENSES
-- -------------------------------------------------------------
create table licenses (
  key text primary key,
  outlet_id text references outlets(id),
  outlet_name text,
  is_active boolean default true,
  activated_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────
create table users (
  id text primary key,
  name text not null,
  pin text not null,
  role text not null check (role in ('owner', 'cashier')),
  outlet_id text references outlets(id),
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- CATEGORIES
-- ─────────────────────────────────────────────
create table categories (
  id text primary key,
  outlet_id text references outlets(id) not null,
  name text not null,
  sort_order integer default 0,
  color_hex text default '#888888',
  is_active boolean default true,
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- PRODUCTS
-- ─────────────────────────────────────────────
create table products (
  id text primary key,
  outlet_id text references outlets(id) not null,
  category_id text references categories(id),
  name text not null,
  description text,
  price text not null,
  cogs text default '0',
  image_url text,
  is_available boolean default true,
  track_stock boolean default false,
  stock text default '0',
  low_stock_alert text default '5',
  sort_order integer default 0,
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- PRODUCT VARIANTS
-- ─────────────────────────────────────────────
create table product_variants (
  id text primary key,
  product_id text references products(id) on delete cascade not null,
  name text not null,
  options jsonb not null default '[]',
  is_required boolean default false,
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- RESTAURANT TABLES
-- ─────────────────────────────────────────────
create table restaurant_tables (
  id text primary key,
  outlet_id text references outlets(id) not null,
  table_label text not null,
  area text,
  capacity integer default 4,
  status text default 'available' check (status in ('available','occupied','reserved','cleaning')),
  current_order_id text,
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- ORDERS
-- ─────────────────────────────────────────────
create table orders (
  id text primary key,
  outlet_id text references outlets(id) not null,
  order_number text not null,
  type text not null check (type in ('dine_in','takeaway','delivery')),
  status text not null check (status in ('open','in_kitchen','ready','paid','void','hold')),
  table_id text,
  table_label text,
  cashier_id text not null,
  cashier_name text not null,
  customer_name text,
  customer_count text,
  notes text,
  subtotal text default '0',
  discount_amount text default '0',
  discount_percent text default '0',
  tax_amount text default '0',
  service_charge text default '0',
  total text default '0',
  payment_method text check (payment_method in ('cash','qris','transfer')),
  paid_amount text,
  change_amount text,
  payment_ref text,
  paid_at timestamptz,
  void_reason text,
  voided_by text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- ORDER ITEMS
-- ─────────────────────────────────────────────
create table order_items (
  id text primary key,
  order_id text references orders(id) not null,
  product_id text not null,
  product_name text not null,
  variant_summary text,
  unit_price text not null,
  quantity text not null,
  discount text default '0',
  subtotal text not null,
  notes text,
  status text default 'pending' check (status in ('pending','cooking','ready','served','cancelled')),
  created_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- SESSIONS (shift)
-- ─────────────────────────────────────────────
create table sessions (
  id text primary key,
  outlet_id text references outlets(id) not null,
  cashier_id text not null,
  cashier_name text not null,
  opening_cash text default '0',
  closing_cash text,
  total_cash_sales text default '0',
  total_qris_sales text default '0',
  total_orders integer default 0,
  total_voids integer default 0,
  notes text,
  opened_at timestamptz default now(),
  closed_at timestamptz
);

-- ─────────────────────────────────────────────
-- INDEXES untuk performa query
-- ─────────────────────────────────────────────
create index idx_orders_outlet_status on orders(outlet_id, status);
create index idx_orders_outlet_paid_at on orders(outlet_id, paid_at);
create index idx_orders_created_at on orders(created_at desc);
create index idx_order_items_order_id on order_items(order_id);
create index idx_products_outlet_id on products(outlet_id, is_available);
create index idx_sessions_outlet_cashier on sessions(outlet_id, cashier_id);

-- ─────────────────────────────────────────────
-- ROW LEVEL SECURITY (RLS)
-- ─────────────────────────────────────────────
-- Enable RLS di semua tabel
alter table outlets enable row level security;
alter table licenses enable row level security;
alter table users enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table restaurant_tables enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table sessions enable row level security;

-- Never put a service_role key in the mobile app.
-- Production sync must go through Edge Functions/server APIs or authenticated
-- RLS policies scoped to a single outlet.

-- Direct table access is intentionally denied by the hardening block below.
-- Use SECURITY DEFINER RPCs or a server-side API for production sync.

-- ─────────────────────────────────────────────
-- REALTIME (opsional — untuk kitchen display)
-- ─────────────────────────────────────────────
-- Di Supabase dashboard: Table Editor → Enable Realtime untuk tabel orders dan order_items
-- Atau via SQL:
-- alter publication supabase_realtime add table orders;
-- alter publication supabase_realtime add table order_items;

-- =============================================
-- SECURITY HARDENING - RUN BEFORE HOSTING
-- =============================================
-- Secure default: no direct anon/authenticated table access.
-- The mobile app may only activate licenses through SECURITY DEFINER RPCs.
alter table outlets enable row level security;
alter table licenses enable row level security;
alter table users enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table product_variants enable row level security;
alter table restaurant_tables enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table sessions enable row level security;

drop policy if exists "outlet_access" on outlets;
drop policy if exists "outlet_access" on licenses;
drop policy if exists "outlet_access" on users;
drop policy if exists "outlet_access" on categories;
drop policy if exists "outlet_access" on products;
drop policy if exists "outlet_access" on product_variants;
drop policy if exists "outlet_access" on restaurant_tables;
drop policy if exists "outlet_access" on orders;
drop policy if exists "outlet_access" on order_items;
drop policy if exists "outlet_access" on sessions;

drop policy if exists "deny_direct_access" on outlets;
drop policy if exists "deny_direct_access" on licenses;
drop policy if exists "deny_direct_access" on users;
drop policy if exists "deny_direct_access" on categories;
drop policy if exists "deny_direct_access" on products;
drop policy if exists "deny_direct_access" on product_variants;
drop policy if exists "deny_direct_access" on restaurant_tables;
drop policy if exists "deny_direct_access" on orders;
drop policy if exists "deny_direct_access" on order_items;
drop policy if exists "deny_direct_access" on sessions;

create policy "deny_direct_access" on outlets
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on licenses
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on users
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on categories
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on products
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on product_variants
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on restaurant_tables
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on orders
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on order_items
  for all to anon, authenticated using (false) with check (false);
create policy "deny_direct_access" on sessions
  for all to anon, authenticated using (false) with check (false);

revoke all on table
  outlets,
  licenses,
  users,
  categories,
  products,
  product_variants,
  restaurant_tables,
  orders,
  order_items,
  sessions
from anon, authenticated;

create or replace function normalize_license_key(p_key text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(p_key, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function validate_license(p_key text)
returns table (
  license_key text,
  outlet_id text,
  outlet_name text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select l.key, l.outlet_id, l.outlet_name, l.expires_at
  from licenses l
  where normalize_license_key(l.key) = normalize_license_key(p_key)
    and l.is_active = true
    and l.activated_at is null
    and (l.expires_at is null or l.expires_at > now())
  limit 1;
end;
$$;

create or replace function activate_license(
  p_key text,
  p_outlet_name text,
  p_address text default null,
  p_phone text default null
)
returns table (
  outlet_id text,
  license_key text,
  outlet_name text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  license_row licenses%rowtype;
  resolved_outlet_id text;
  resolved_outlet_name text;
begin
  select *
    into license_row
  from licenses l
  where normalize_license_key(l.key) = normalize_license_key(p_key)
    and l.is_active = true
    and (l.expires_at is null or l.expires_at > now())
  for update;

  if not found then
    raise exception 'LICENSE_INVALID';
  end if;

  if license_row.activated_at is not null then
    raise exception 'LICENSE_ALREADY_USED';
  end if;

  resolved_outlet_id := coalesce(license_row.outlet_id, uuid_generate_v4()::text);
  resolved_outlet_name := coalesce(
    nullif(trim(p_outlet_name), ''),
    nullif(trim(license_row.outlet_name), ''),
    'Outlet'
  );

  insert into outlets (
    id,
    name,
    address,
    phone,
    license_key,
    license_expiry,
    is_setup_done
  )
  values (
    resolved_outlet_id,
    resolved_outlet_name,
    nullif(trim(coalesce(p_address, '')), ''),
    nullif(trim(coalesce(p_phone, '')), ''),
    license_row.key,
    license_row.expires_at,
    true
  )
  on conflict (id) do update set
    name = excluded.name,
    address = excluded.address,
    phone = excluded.phone,
    license_key = excluded.license_key,
    license_expiry = excluded.license_expiry,
    is_setup_done = true;

  update licenses
  set outlet_id = resolved_outlet_id,
      outlet_name = resolved_outlet_name,
      activated_at = now()
  where key = license_row.key;

  return query
  select resolved_outlet_id, license_row.key, resolved_outlet_name, license_row.expires_at;
end;
$$;

revoke all on function normalize_license_key(text) from public;
revoke all on function validate_license(text) from public;
revoke all on function activate_license(text, text, text, text) from public;
grant execute on function validate_license(text) to anon, authenticated;
grant execute on function activate_license(text, text, text, text) to anon, authenticated;
