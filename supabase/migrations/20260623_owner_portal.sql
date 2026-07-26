-- Sajia Owner Portal: organisasi, akses cabang, dan laporan konsolidasi.
-- Jalankan migration ini di Supabase sebelum memakai dashboard owner web.

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

-- Pengeluaran cloud. Mobile sync untuk tabel ini akan ditambahkan melalui API
-- terautentikasi; dashboard owner tidak memberi akses tabel secara langsung.
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

alter table organizations enable row level security;
alter table organization_members enable row level security;
alter table outlet_organizations enable row level security;
alter table expenses enable row level security;

revoke all on table organizations, organization_members, outlet_organizations, expenses
from anon, authenticated;

-- Membuat organisasi pertama berdasarkan outlet yang owner_email-nya sama
-- dengan email Supabase Auth. Function dapat dipanggil ulang untuk mengaitkan
-- cabang baru dengan owner yang sama.
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

-- Ringkasan laporan konsolidasi untuk portal owner. Data mentah tetap tertutup
-- oleh RLS; browser hanya menerima angka yang memang dibutuhkan dashboard.
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

revoke all on function ensure_owner_organization() from public;
revoke all on function get_owner_dashboard(timestamptz, timestamptz) from public;
grant execute on function ensure_owner_organization() to authenticated;
grant execute on function get_owner_dashboard(timestamptz, timestamptz)
  to authenticated;
