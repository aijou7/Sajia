-- Owner-managed recipe and HPP buffer. products.cogs remains the effective
-- per-portion HPP consumed by every shipped cashier version.
create table if not exists public.product_cost_profiles (
  product_id text primary key references public.products(id) on delete cascade,
  outlet_id text not null,
  base_cogs numeric not null check (base_cogs >= 0),
  buffer_percent smallint not null default 0
    check (buffer_percent in (0, 5, 10)),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

create index if not exists product_cost_profiles_outlet_idx
  on public.product_cost_profiles(outlet_id);

alter table public.product_cost_profiles enable row level security;
revoke all on public.product_cost_profiles from public, anon, authenticated;
grant select on public.product_cost_profiles to authenticated;

drop policy if exists owner_read_product_cost_profiles
  on public.product_cost_profiles;
create policy owner_read_product_cost_profiles
  on public.product_cost_profiles for select to authenticated
  using (public.current_user_has_outlet(outlet_id));

-- Existing APKs upsert all the product fields they know. Once costing has
-- been configured in the owner dashboard, those writes may still change
-- name/price/availability but cannot overwrite the authoritative HPP.
create or replace function public.preserve_owner_managed_product_cogs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  profile public.product_cost_profiles%rowtype;
begin
  if current_setting('app.owner_cost_write', true) = 'true' then
    return new;
  end if;

  select * into profile
  from public.product_cost_profiles
  where product_id = old.id;
  if found then
    if new.outlet_id is distinct from old.outlet_id then
      raise exception 'OWNER_COSTING_OUTLET_LOCKED';
    end if;
    new.cogs := round(
      profile.base_cogs * (100 + profile.buffer_percent) / 100
    )::text;
  end if;
  return new;
end;
$$;

drop trigger if exists preserve_owner_managed_product_cogs
  on public.products;
create trigger preserve_owner_managed_product_cogs
before update on public.products
for each row execute function public.preserve_owner_managed_product_cogs();

-- An offline APK can still sell using products.cogs. Recipe edits for an
-- owner-managed menu must go through the atomic dashboard operation.
create or replace function public.guard_owner_managed_cost_components()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product_id text;
begin
  if current_setting('app.owner_cost_write', true) = 'true' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_product_id := case when tg_op = 'INSERT' then new.product_id
                       else old.product_id end;
  -- Serialize a legacy component write with the owner RPC's product lock.
  -- Otherwise an offline insert could pass the profile check just before
  -- the profile is created, then commit after the owner's replacement.
  perform 1 from public.products
  where id = v_product_id
  for share;

  if exists (
    select 1 from public.product_cost_profiles
    where product_id = v_product_id
  ) and not (
    tg_op = 'DELETE' and exists (
      select 1 from public.sync_tombstones
      where entity_type = 'product' and record_id = v_product_id
        and outlet_id = old.outlet_id
    )
  ) then
    raise exception 'OWNER_COSTING_MANAGED_IN_DASHBOARD';
  end if;
  if tg_op = 'UPDATE' then
    if exists (
      select 1 from public.product_cost_profiles
      where product_id = new.product_id
    ) then
      raise exception 'OWNER_COSTING_MANAGED_IN_DASHBOARD';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists guard_owner_managed_cost_components
  on public.product_cost_components;
create trigger guard_owner_managed_cost_components
before insert or update or delete on public.product_cost_components
for each row execute function public.guard_owner_managed_cost_components();

create or replace function public.save_owner_product_with_costing(
  p_product jsonb,
  p_components jsonb,
  p_expected_updated_at timestamptz default null,
  p_expected_cost_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_product public.products%rowtype;
  existing_profile public.product_cost_profiles%rowtype;
  component jsonb;
  v_product_id text := nullif(btrim(p_product->>'id'), '');
  v_outlet_id text := nullif(btrim(p_product->>'outlet_id'), '');
  v_name text := nullif(btrim(p_product->>'name'), '');
  v_price numeric;
  v_base numeric;
  v_buffer smallint;
  v_effective numeric;
  v_revision bigint;
  v_component_id text;
  v_component_ids text[] := array[]::text[];
  v_package_unit text;
  v_recipe_unit text;
  v_package_factor numeric;
  v_recipe_factor numeric;
  v_package_quantity numeric;
  v_recipe_quantity numeric;
  v_package_price numeric;
begin
  if auth.uid() is null or v_product_id is null or v_outlet_id is null
      or not public.current_user_has_outlet(v_outlet_id) then
    raise exception 'OWNER_ACCESS_REQUIRED';
  end if;
  if v_name is null or jsonb_typeof(p_components) is distinct from 'array' then
    raise exception 'INVALID_PRODUCT_COSTING';
  end if;
  if jsonb_array_length(p_components) > 200 then
    raise exception 'INVALID_PRODUCT_COSTING';
  end if;

  v_price := (p_product->>'price')::numeric;
  v_base := (p_product->>'base_cogs')::numeric;
  v_buffer := (p_product->>'buffer_percent')::smallint;
  if v_price <= 0 or v_base < 0 or v_buffer not in (0, 5, 10)
      or v_price is null or v_base is null or v_buffer is null then
    raise exception 'INVALID_PRODUCT_COSTING';
  end if;
  if p_product->>'category_id' is not null and not exists (
    select 1 from public.categories
    where id = p_product->>'category_id' and outlet_id = v_outlet_id
  ) then
    raise exception 'INVALID_CATEGORY';
  end if;

  select * into existing_product
  from public.products
  where id = v_product_id
  for update;
  if found then
    if existing_product.outlet_id <> v_outlet_id
        or existing_product.updated_at is distinct from p_expected_updated_at then
      raise exception 'PRODUCT_CHANGED_RELOAD';
    end if;
  elsif p_expected_updated_at is not null then
    raise exception 'PRODUCT_CHANGED_RELOAD';
  end if;

  select * into existing_profile
  from public.product_cost_profiles
  where product_id = v_product_id
  for update;
  if found then
    if p_expected_cost_revision is distinct from existing_profile.revision then
      raise exception 'PRODUCT_COST_CHANGED_RELOAD';
    end if;
    v_revision := existing_profile.revision + 1;
  elsif p_expected_cost_revision is not null then
    raise exception 'PRODUCT_COST_CHANGED_RELOAD';
  else
    v_revision := 1;
  end if;

  if jsonb_array_length(p_components) > 0 then
    v_base := 0;
  end if;
  for component in select value from jsonb_array_elements(p_components) loop
    v_component_id := nullif(btrim(component->>'id'), '');
    v_package_unit := component->>'package_unit';
    v_recipe_unit := component->>'recipe_unit';
    v_package_quantity := (component->>'package_quantity')::numeric;
    v_recipe_quantity := (component->>'recipe_quantity')::numeric;
    v_package_price := (component->>'package_price')::numeric;
    if v_component_id is null or nullif(btrim(component->>'material_name'), '') is null
        or v_component_id = any(v_component_ids)
        or v_package_quantity is null or v_package_quantity <= 0
        or v_recipe_quantity is null or v_recipe_quantity <= 0
        or v_package_price is null or v_package_price < 0
        or exists (
          select 1 from public.product_cost_components
          where id = v_component_id
            and (product_id <> v_product_id or outlet_id <> v_outlet_id)
        ) then
      raise exception 'INVALID_RECIPE_COMPONENT';
    end if;
    v_package_factor := case v_package_unit
      when 'gram' then 1 when 'kilogram' then 1000
      when 'milliliter' then 1 when 'liter' then 1000
      when 'piece' then 1 else null end;
    v_recipe_factor := case v_recipe_unit
      when 'gram' then 1 when 'kilogram' then 1000
      when 'milliliter' then 1 when 'liter' then 1000
      when 'piece' then 1 else null end;
    if v_package_factor is null or v_recipe_factor is null
        or not (
          (v_package_unit in ('gram', 'kilogram') and v_recipe_unit in ('gram', 'kilogram'))
          or (v_package_unit in ('milliliter', 'liter') and v_recipe_unit in ('milliliter', 'liter'))
          or (v_package_unit = 'piece' and v_recipe_unit = 'piece')
        ) then
      raise exception 'INCOMPATIBLE_RECIPE_UNITS';
    end if;
    v_base := v_base +
      v_package_price * v_recipe_quantity * v_recipe_factor /
      (v_package_quantity * v_package_factor);
    v_component_ids := array_append(v_component_ids, v_component_id);
  end loop;

  v_effective := round(v_base * (100 + v_buffer) / 100);
  perform set_config('app.owner_cost_write', 'true', true);

  if existing_product.id is null then
    insert into public.products (
      id, outlet_id, category_id, name, description, price, cogs,
      is_available, track_stock, stock, low_stock_alert, sort_order, updated_at
    ) values (
      v_product_id, v_outlet_id, p_product->>'category_id', v_name,
      nullif(btrim(p_product->>'description'), ''), v_price::text,
      v_effective::text,
      coalesce((p_product->>'is_available')::boolean, true),
      coalesce((p_product->>'track_stock')::boolean, false),
      coalesce((p_product->>'stock')::numeric, 0)::text,
      coalesce((p_product->>'low_stock_alert')::numeric, 5)::text,
      0, clock_timestamp()
    );
  end if;

  insert into public.product_cost_profiles (
    product_id, outlet_id, base_cogs, buffer_percent, revision, updated_at
  ) values (
    v_product_id, v_outlet_id, v_base, v_buffer, v_revision, clock_timestamp()
  ) on conflict (product_id) do update set
    base_cogs = excluded.base_cogs,
    buffer_percent = excluded.buffer_percent,
    revision = excluded.revision,
    updated_at = excluded.updated_at;

  for component in select value from jsonb_array_elements(p_components) loop
    insert into public.product_cost_components (
      id, outlet_id, product_id, material_name, package_quantity,
      package_unit, package_price, recipe_quantity, recipe_unit, updated_at
    ) values (
      component->>'id', v_outlet_id, v_product_id,
      btrim(component->>'material_name'),
      (component->>'package_quantity')::numeric,
      component->>'package_unit',
      (component->>'package_price')::numeric,
      (component->>'recipe_quantity')::numeric,
      component->>'recipe_unit', clock_timestamp()
    ) on conflict (id) do update set
      material_name = excluded.material_name,
      package_quantity = excluded.package_quantity,
      package_unit = excluded.package_unit,
      package_price = excluded.package_price,
      recipe_quantity = excluded.recipe_quantity,
      recipe_unit = excluded.recipe_unit,
      updated_at = excluded.updated_at
    where public.product_cost_components.product_id = v_product_id
      and public.product_cost_components.outlet_id = v_outlet_id;
    if not found then
      raise exception 'INVALID_RECIPE_COMPONENT';
    end if;
  end loop;

  delete from public.product_cost_components
  where product_id = v_product_id and outlet_id = v_outlet_id
    and not (id = any(v_component_ids));

  update public.products set
    category_id = p_product->>'category_id',
    name = v_name,
    description = nullif(btrim(p_product->>'description'), ''),
    price = v_price::text,
    cogs = v_effective::text,
    is_available = coalesce((p_product->>'is_available')::boolean, true),
    low_stock_alert = coalesce((p_product->>'low_stock_alert')::numeric, 5)::text,
    updated_at = clock_timestamp()
  where id = v_product_id and outlet_id = v_outlet_id;

  perform set_config('app.owner_cost_write', 'false', true);

  return jsonb_build_object(
    'product_id', v_product_id,
    'revision', v_revision,
    'base_cogs', v_base,
    'buffer_percent', v_buffer,
    'cogs', v_effective
  );
end;
$$;

revoke all on function public.save_owner_product_with_costing(
  jsonb, jsonb, timestamptz, bigint
) from public, anon;
grant execute on function public.save_owner_product_with_costing(
  jsonb, jsonb, timestamptz, bigint
) to authenticated;

-- Historical sales may not have a transaction-time HPP snapshot. Never
-- substitute today's menu HPP: a costing edit must not rewrite past profit.
create or replace function public.get_owner_dashboard(
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

  perform public.ensure_owner_organization();
  if not exists (
    select 1 from public.organization_members member
    where member.user_id = current_user_id
      and member.role in ('owner', 'admin')
  ) then
    raise exception 'OWNER_ACCESS_REQUIRED';
  end if;

  with accessible_outlets as (
    select distinct outlet.id, outlet.name
    from public.outlets outlet
    join public.outlet_organizations outlet_org
      on outlet_org.outlet_id = outlet.id
    join public.organization_members member
      on member.organization_id = outlet_org.organization_id
    where member.user_id = current_user_id
      and member.role in ('owner', 'admin')
      and public.current_user_has_cloud_outlet(outlet.id)
      and not (
        outlet.id = 'default-outlet'
        and lower(btrim(outlet.name)) = 'nama kafe saya'
      )
  ),
  paid_orders as (
    select order_row.id, order_row.outlet_id,
      coalesce(nullif(order_row.total, '')::numeric, 0) as total
    from public.orders order_row
    join accessible_outlets outlet on outlet.id = order_row.outlet_id
    where order_row.status = 'paid'
      and order_row.paid_at >= p_from
      and order_row.paid_at <= p_to
  ),
  revenue_by_outlet as (
    select outlet_id, coalesce(sum(total), 0) as revenue,
      count(*)::integer as transactions
    from paid_orders group by outlet_id
  ),
  sold_items as (
    select paid.outlet_id,
      case when item.quantity ~ '^[0-9]+(\.[0-9]+)?$'
        then item.quantity::numeric else 0 end as quantity,
      case when item.unit_cogs ~ '^[0-9]+(\.[0-9]+)?$'
        then item.unit_cogs::numeric else null end as unit_cogs
    from paid_orders paid
    join public.order_items item on item.order_id = paid.id
  ),
  cogs_by_outlet as (
    select outlet_id,
      coalesce(sum(coalesce(unit_cogs, 0) * quantity), 0) as cogs,
      coalesce(sum(quantity), 0) as sold_quantity,
      coalesce(sum(case when unit_cogs is null then 0 else quantity end), 0)
        as covered_quantity
    from sold_items group by outlet_id
  ),
  expenses_by_outlet as (
    select expense.outlet_id,
      coalesce(sum(coalesce(nullif(expense.amount, '')::numeric, 0)), 0)
        as expenses
    from public.expenses expense
    join accessible_outlets outlet on outlet.id = expense.outlet_id
    where expense.occurred_at >= p_from and expense.occurred_at <= p_to
    group by expense.outlet_id
  ),
  branches as (
    select outlet.id as outlet_id, outlet.name as outlet_name,
      coalesce(revenue.revenue, 0) as revenue,
      coalesce(cogs.cogs, 0) as cogs,
      coalesce(expense.expenses, 0) as expenses,
      coalesce(revenue.transactions, 0) as transactions,
      coalesce(cogs.sold_quantity, 0) as sold_quantity,
      coalesce(cogs.covered_quantity, 0) as covered_quantity,
      case when coalesce(revenue.transactions, 0) = 0 then 1::numeric
        when coalesce(cogs.sold_quantity, 0) = 0 then 0::numeric
        else least(1, cogs.covered_quantity / cogs.sold_quantity)
      end as hpp_coverage_ratio
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
    'hpp_coverage_ratio',
      case when coalesce(sum(transactions), 0) = 0 then 1::numeric
        when coalesce(sum(sold_quantity), 0) = 0 then 0::numeric
        else least(1, sum(covered_quantity) / sum(sold_quantity)) end,
    'cloud_required', count(*) = 0,
    'branches', coalesce(
      jsonb_agg(jsonb_build_object(
        'outlet_id', outlet_id,
        'outlet_name', outlet_name,
        'revenue', revenue,
        'cogs', cogs,
        'expenses', expenses,
        'transactions', transactions,
        'hpp_coverage_ratio', hpp_coverage_ratio,
        'net_profit', case when hpp_coverage_ratio >= 1
          then revenue - cogs - expenses else null end
      ) order by revenue desc),
      '[]'::jsonb
    )
  ) into dashboard from branches;

  return dashboard;
end;
$$;

revoke all on function public.get_owner_dashboard(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.get_owner_dashboard(timestamptz, timestamptz)
  to authenticated;
