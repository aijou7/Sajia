-- Remove the obsolete onboarding placeholder without touching any real outlet.
-- The WHERE clause is intentionally exact, and the delete is safe because the
-- known production row was verified to have no operational data.
delete from outlets
where id = 'default-outlet'
  and lower(btrim(name)) = 'nama kafe saya';

-- A device running an older APK must not be able to recreate the obsolete row.
create or replace function reject_legacy_placeholder_outlet()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.id = 'default-outlet'
      and lower(btrim(new.name)) = 'nama kafe saya' then
    raise exception 'LEGACY_PLACEHOLDER_OUTLET_NOT_ALLOWED'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists reject_legacy_placeholder_outlet_before_write on outlets;
create trigger reject_legacy_placeholder_outlet_before_write
before insert or update of id, name on outlets
for each row execute function reject_legacy_placeholder_outlet();

revoke all on function reject_legacy_placeholder_outlet() from public;

-- Keep historical placeholder rows out of both app recovery and the owner web
-- dashboard even if a database predating the cleanup is inspected.
create or replace function get_authenticated_owner_outlets()
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
    and not (
      outlet.id = 'default-outlet'
      and lower(btrim(outlet.name)) = 'nama kafe saya'
    )
    and (
      lower(coalesce(outlet.owner_email, '')) =
        lower(coalesce(auth.jwt() ->> 'email', ''))
      or current_user_has_outlet(outlet.id)
    )
  order by outlet.created_at asc;
$$;

create or replace function get_owner_outlets()
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
    and not (
      outlet.id = 'default-outlet'
      and lower(btrim(outlet.name)) = 'nama kafe saya'
    )
  order by outlet.created_at asc;
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
      and current_user_has_cloud_outlet(outlet.id)
      and not (
        outlet.id = 'default-outlet'
        and lower(btrim(outlet.name)) = 'nama kafe saya'
      )
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
    select outlet_id, coalesce(sum(total), 0) as revenue,
      count(*)::integer as transactions
    from paid_orders
    group by outlet_id
  ),
  cogs_by_outlet as (
    select paid.outlet_id,
      coalesce(sum(
        coalesce(
          nullif(item.unit_cogs, '')::numeric,
          nullif(product.cogs, '')::numeric,
          0
        ) * coalesce(nullif(item.quantity, '')::numeric, 0)
      ), 0) as cogs
    from paid_orders paid
    join order_items item on item.order_id = paid.id
    left join products product on product.id = item.product_id
    group by paid.outlet_id
  ),
  expenses_by_outlet as (
    select expense.outlet_id,
      coalesce(sum(coalesce(nullif(expense.amount, '')::numeric, 0)), 0)
        as expenses
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
    'cloud_required', count(*) = 0,
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

revoke all on function get_authenticated_owner_outlets() from public;
grant execute on function get_authenticated_owner_outlets() to authenticated;
revoke all on function get_owner_outlets() from public;
grant execute on function get_owner_outlets() to authenticated;
revoke all on function get_owner_dashboard(timestamptz, timestamptz)
  from public, anon;
grant execute on function get_owner_dashboard(timestamptz, timestamptz)
  to authenticated;
