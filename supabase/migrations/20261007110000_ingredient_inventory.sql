-- Purchases create inventory, sales consume it, and internal use is an
-- operating expense. Purchases never enter expenses (avoids double HPP).
create table if not exists public.ingredients (
  id text primary key, outlet_id text not null references public.outlets(id),
  name text not null check (length(name) between 1 and 100),
  unit text not null check (unit in ('gram', 'milliliter', 'piece')),
  quantity numeric not null default 0 check (abs(quantity) < 1e12),
  unit_cost numeric not null default 0 check (unit_cost >= 0 and unit_cost < 1e12),
  updated_at timestamptz not null default now()
);
create unique index if not exists ingredients_name_unique on public.ingredients(outlet_id, lower(name));
create table if not exists public.ingredient_purchases (
  id text primary key, outlet_id text not null references public.outlets(id),
  occurred_at timestamptz not null, note text, items jsonb not null,
  total numeric not null, request_hash text not null, created_at timestamptz not null default now()
);
create table if not exists public.ingredient_movements (
  id bigint generated always as identity primary key,
  outlet_id text not null references public.outlets(id),
  ingredient_id text not null references public.ingredients(id),
  source_type text not null check (source_type in ('purchase', 'sale', 'void', 'internal')),
  source_id text not null, quantity numeric not null, unit_cost numeric not null,
  occurred_at timestamptz not null, created_at timestamptz not null default now(),
  unique(source_type, source_id, ingredient_id)
);
create index if not exists ingredient_movements_outlet_date on public.ingredient_movements(outlet_id, occurred_at);
create table if not exists public.inventory_recipe_versions (
  id bigint generated always as identity primary key, product_id text not null,
  outlet_id text not null references public.outlets(id),
  effective_from timestamptz not null default clock_timestamp(),
  cogs numeric not null, components jsonb not null,
  product_name text not null default '', has_untracked_materials boolean not null default true
);
create index if not exists inventory_recipe_lookup on public.inventory_recipe_versions(product_id, effective_from desc, id desc);
create table if not exists public.ingredient_sale_items (
  item_id text primary key, order_id text not null, outlet_id text not null,
  product_id text not null, quantity numeric not null, components jsonb not null,
  reversed boolean not null default false
);
create index if not exists ingredient_sale_items_order on public.ingredient_sale_items(order_id);
create table if not exists public.internal_material_usage (
  id text primary key, outlet_id text not null references public.outlets(id),
  purpose text not null check (purpose in ('rnd', 'personal', 'waste')),
  occurred_at timestamptz not null, note text, items jsonb not null,
  total_cogs numeric not null, request_hash text not null,
  has_untracked_materials boolean not null default false, created_at timestamptz not null default now()
);
alter table public.product_cost_components add column if not exists ingredient_id text references public.ingredients(id);

create or replace function public.validate_inventory_component_scope()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.products where id = new.product_id and outlet_id = new.outlet_id) then
    raise exception 'INVALID_RECIPE_PRODUCT_SCOPE';
  end if;
  if new.ingredient_id is not null and not exists(select 1 from public.ingredients where id = new.ingredient_id and outlet_id = new.outlet_id) then
    raise exception 'INVALID_INGREDIENT_SCOPE';
  end if;
  return new;
end; $$;
drop trigger if exists validate_inventory_component_scope on public.product_cost_components;
create trigger validate_inventory_component_scope before insert or update on public.product_cost_components
  for each row execute function public.validate_inventory_component_scope();

-- Balances, valuation, and movement history can only be written by the RPCs.
do $$ declare t text; begin
  foreach t in array array['ingredients', 'ingredient_purchases', 'ingredient_movements',
      'inventory_recipe_versions', 'internal_material_usage'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists inventory_owner_read on public.%I', t);
    execute format('create policy inventory_owner_read on public.%I for select to authenticated using (public.current_user_has_cloud_outlet(outlet_id))', t);
  end loop;
end $$;
alter table public.ingredient_sale_items enable row level security;
revoke all on public.ingredient_sale_items from public, anon, authenticated;

create or replace function public.inventory_unit_factor(p_unit text)
returns numeric language sql immutable set search_path = '' as $$
  select case p_unit when 'gram' then 1 when 'milliliter' then 1 when 'piece' then 1
    when 'kilogram' then 1000 when 'liter' then 1000 else null end;
$$;
revoke all on function public.inventory_unit_factor(text) from public, anon, authenticated;

create or replace function public.save_owner_ingredient(p_id text, p_outlet_id text, p_name text, p_unit text)
returns boolean language plpgsql security definer set search_path = public as $$
declare existing public.ingredients%rowtype;
begin
  if auth.uid() is null or not public.current_user_has_outlet(p_outlet_id) then raise exception 'OWNER_ACCESS_REQUIRED'; end if;
  if not public.current_user_has_cloud_outlet(p_outlet_id) then raise exception 'CLOUD_REQUIRED'; end if;
  if p_id is null or length(btrim(p_name)) not between 1 and 100 or p_name is null
      or p_unit not in ('gram', 'milliliter', 'piece') or p_unit is null then raise exception 'INVALID_INGREDIENT'; end if;
  perform 1 from public.outlets where id = p_outlet_id for no key update;
  select * into existing from public.ingredients where id = p_id for update;
  if found and (existing.outlet_id <> p_outlet_id or existing.unit <> p_unit) then raise exception 'INGREDIENT_UNIT_LOCKED'; end if;
  insert into public.ingredients(id, outlet_id, name, unit) values(p_id, p_outlet_id, btrim(p_name), p_unit)
    on conflict(id) do update set name = excluded.name, updated_at = clock_timestamp();
  return true;
end; $$;

-- Store recipe/HPP revisions so an offline sale consumes the recipe that was
-- effective at checkout time, even when the owner edits it before upload.
create or replace function public.snapshot_inventory_recipe(p_product_id text)
returns void language plpgsql security definer set search_path = public as $$
declare p public.products%rowtype; lines jsonb; previous public.inventory_recipe_versions%rowtype;
begin
  select * into p from public.products where id = p_product_id;
  if not found then return; end if;
  select coalesce(jsonb_agg(jsonb_build_object('ingredient_id', c.ingredient_id,
      'quantity', c.quantity, 'unit_cost', c.cost / c.quantity) order by c.ingredient_id), '[]'::jsonb)
    into lines from (
      select ingredient_id,
        sum(recipe_quantity * public.inventory_unit_factor(recipe_unit)) as quantity,
        sum(package_price * recipe_quantity * public.inventory_unit_factor(recipe_unit)
          / (package_quantity * public.inventory_unit_factor(package_unit))) as cost
      from public.product_cost_components where product_id = p.id and ingredient_id is not null group by ingredient_id
    ) c;
  select * into previous from public.inventory_recipe_versions where product_id = p.id order by effective_from desc, id desc limit 1;
  if found and previous.components = lines and previous.cogs = p.cogs::numeric and previous.product_name = p.name
      and previous.has_untracked_materials = (jsonb_array_length(lines) = 0 or exists (
        select 1 from public.product_cost_components where product_id = p.id and ingredient_id is null)) then return; end if;
  insert into public.inventory_recipe_versions(product_id, outlet_id, cogs, components, product_name, has_untracked_materials)
    values(p.id, p.outlet_id, coalesce(nullif(p.cogs, '')::numeric, 0), lines, p.name,
      jsonb_array_length(lines) = 0 or exists (select 1 from public.product_cost_components where product_id = p.id and ingredient_id is null));
end; $$;

-- Preserve the old RPC signature for old dashboards and installed APKs.
do $$ begin
  if to_regprocedure('public.save_owner_product_costing_legacy(jsonb,jsonb,timestamp with time zone,bigint)') is null then
    alter function public.save_owner_product_with_costing(jsonb,jsonb,timestamptz,bigint) rename to save_owner_product_costing_legacy;
  end if;
end $$;
revoke all on function public.save_owner_product_costing_legacy(jsonb,jsonb,timestamptz,bigint) from public, anon, authenticated;
create or replace function public.save_owner_product_with_costing(
  p_product jsonb, p_components jsonb, p_expected_updated_at timestamptz default null, p_expected_cost_revision bigint default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare c jsonb; normalized jsonb := '[]'; ing public.ingredients%rowtype;
  ingredient text; recipe_unit text; v_product_id text := p_product->>'id'; v_outlet_id text := p_product->>'outlet_id'; result jsonb;
begin
  if auth.uid() is null or not public.current_user_has_outlet(v_outlet_id) then raise exception 'OWNER_ACCESS_REQUIRED'; end if;
  if jsonb_typeof(p_components) is distinct from 'array' or jsonb_array_length(p_components) > 200 then raise exception 'INVALID_PRODUCT_COSTING'; end if;
  perform 1 from public.outlets where id = v_outlet_id for no key update;
  for c in select value from jsonb_array_elements(p_components) loop
    ingredient := c->>'ingredient_id';
    -- Old dashboard versions omit the field; retain an existing association.
    if not (c ? 'ingredient_id') then
      select ingredient_id into ingredient from public.product_cost_components where id = c->>'id' and product_id = v_product_id and outlet_id = v_outlet_id;
    end if;
    if ingredient is not null then
      if not public.current_user_has_cloud_outlet(v_outlet_id) then raise exception 'CLOUD_REQUIRED'; end if;
      select * into ing from public.ingredients where id = ingredient and outlet_id = v_outlet_id;
      if not found then raise exception 'INVALID_INGREDIENT'; end if;
      recipe_unit := c->>'recipe_unit';
      if not ((ing.unit = 'gram' and recipe_unit in ('gram', 'kilogram'))
          or (ing.unit = 'milliliter' and recipe_unit in ('milliliter', 'liter'))
          or (ing.unit = 'piece' and recipe_unit = 'piece')) then raise exception 'INCOMPATIBLE_RECIPE_UNITS'; end if;
      c := c || jsonb_build_object('ingredient_id', ing.id, 'material_name', ing.name,
        'package_quantity', 1, 'package_unit', ing.unit, 'package_price', ing.unit_cost);
    end if;
    normalized := normalized || jsonb_build_array(c);
  end loop;
  result := public.save_owner_product_costing_legacy(p_product, normalized, p_expected_updated_at, p_expected_cost_revision);
  perform set_config('app.owner_cost_write', 'true', true);
  for c in select value from jsonb_array_elements(normalized) loop
    update public.product_cost_components set ingredient_id = c->>'ingredient_id' where id = c->>'id' and product_id = v_product_id and outlet_id = v_outlet_id;
  end loop;
  perform set_config('app.owner_cost_write', 'false', true);
  perform public.snapshot_inventory_recipe(v_product_id);
  return result;
end; $$;

create or replace function public.refresh_inventory_recipe_costs(p_outlet_id text)
returns void language plpgsql security definer set search_path = public as $$
declare product text; base numeric; buffer smallint;
begin
  perform set_config('app.owner_cost_write', 'true', true);
  for product in select distinct c.product_id from public.product_cost_components c where c.outlet_id = p_outlet_id and c.ingredient_id is not null order by c.product_id loop
    perform 1 from public.products where id = product for update;
    update public.product_cost_components c set package_quantity = 1, package_unit = i.unit, package_price = i.unit_cost, updated_at = clock_timestamp()
      from public.ingredients i where c.product_id = product and c.ingredient_id = i.id;
    select sum(c.package_price * c.recipe_quantity * public.inventory_unit_factor(c.recipe_unit)
        / (c.package_quantity * public.inventory_unit_factor(c.package_unit))) into base
      from public.product_cost_components c where c.product_id = product;
    select buffer_percent into buffer from public.product_cost_profiles where product_id = product;
    update public.product_cost_profiles set base_cogs = base, revision = revision + 1, updated_at = clock_timestamp() where product_id = product;
    update public.products set cogs = round(base * (100 + coalesce(buffer, 0)) / 100)::text, updated_at = clock_timestamp() where id = product;
    perform public.snapshot_inventory_recipe(product);
  end loop;
  perform set_config('app.owner_cost_write', 'false', true);
end; $$;

create or replace function public.apply_ingredient_movement(p_outlet_id text, p_ingredient_id text,
  p_type text, p_source_id text, p_quantity numeric, p_unit_cost numeric, p_occurred_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare affected integer;
begin
  insert into public.ingredient_movements(outlet_id, ingredient_id, source_type, source_id, quantity, unit_cost, occurred_at)
    values(p_outlet_id, p_ingredient_id, p_type, p_source_id, p_quantity, p_unit_cost, p_occurred_at)
    on conflict(source_type, source_id, ingredient_id) do nothing;
  get diagnostics affected = row_count;
  if affected = 1 then
    -- Negative stock is visible: an offline sale is never silently dropped
    -- or clamped to zero just because another device consumed the last stock.
    update public.ingredients set quantity = quantity + p_quantity, updated_at = clock_timestamp()
      where id = p_ingredient_id and outlet_id = p_outlet_id;
    if not found then raise exception 'INVALID_INGREDIENT'; end if;
  end if;
end; $$;

create or replace function public.record_ingredient_purchase(p_id text, p_outlet_id text, p_items jsonb, p_occurred_at timestamptz, p_note text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare ing public.ingredients%rowtype; c jsonb; q numeric; price numeric; factor numeric; normalized jsonb := '[]'; total numeric := 0;
  fingerprint text := md5(p_items::text || extract(epoch from p_occurred_at)::text || coalesce(p_note, '')); previous public.ingredient_purchases%rowtype; seen text[] := '{}';
begin
  if auth.uid() is null or not public.current_user_has_outlet(p_outlet_id) then raise exception 'OWNER_ACCESS_REQUIRED'; end if;
  if not public.current_user_has_cloud_outlet(p_outlet_id) then raise exception 'CLOUD_REQUIRED'; end if;
  if p_id is null or p_occurred_at is null or p_occurred_at > now() + interval '5 minutes'
      or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200 then raise exception 'INVALID_PURCHASE'; end if;
  perform 1 from public.outlets where id = p_outlet_id for no key update;
  select * into previous from public.ingredient_purchases where id = p_id;
  if found then
    if previous.outlet_id <> p_outlet_id or previous.request_hash <> fingerprint then raise exception 'PURCHASE_ID_CONFLICT'; end if;
    return true;
  end if;
  for c in select value from jsonb_array_elements(p_items) loop
    select * into ing from public.ingredients where id = c->>'ingredient_id' and outlet_id = p_outlet_id for update;
    if not found or ing.id = any(seen) then raise exception 'INVALID_INGREDIENT'; end if;
    seen := array_append(seen, ing.id);
    factor := public.inventory_unit_factor(c->>'unit');
    if factor is null or not ((ing.unit = 'gram' and c->>'unit' in ('gram', 'kilogram'))
        or (ing.unit = 'milliliter' and c->>'unit' in ('milliliter', 'liter'))
        or (ing.unit = 'piece' and c->>'unit' = 'piece')) then raise exception 'INCOMPATIBLE_RECIPE_UNITS'; end if;
    q := (c->>'quantity')::numeric * factor; price := (c->>'price')::numeric;
    if q is null or not (q > 0 and q < 1e12) or price is null or not (price >= 0 and price < 1e12) then raise exception 'INVALID_PURCHASE'; end if;
    update public.ingredients set unit_cost = case when ing.quantity > 0 then
        (ing.quantity * ing.unit_cost + price) / (ing.quantity + q) else price / q end where id = ing.id;
    perform public.apply_ingredient_movement(p_outlet_id, ing.id, 'purchase', p_id, q, price / q, p_occurred_at);
    normalized := normalized || jsonb_build_array(jsonb_build_object('ingredient_id', ing.id, 'name', ing.name,
      'quantity', c->>'quantity', 'unit', c->>'unit', 'price', price));
    total := total + price;
  end loop;
  insert into public.ingredient_purchases(id, outlet_id, occurred_at, note, items, total, request_hash)
    values(p_id, p_outlet_id, p_occurred_at, p_note, normalized, total, fingerprint);
  perform public.refresh_inventory_recipe_costs(p_outlet_id);
  return true;
end; $$;

-- Each uploaded order item has its own durable receipt. This works even for
-- old APKs which never enqueue product-stock events for untracked menus.
create or replace function public.reconcile_ingredient_sale_item(p_item_id text)
returns void language plpgsql security definer set search_path = public as $$
declare item public.order_items%rowtype; sale public.orders%rowtype; applied public.ingredient_sale_items%rowtype;
  recipe public.inventory_recipe_versions%rowtype; c jsonb; lines jsonb; q numeric;
begin
  select * into item from public.order_items where id = p_item_id;
  if not found then return; end if;
  select * into sale from public.orders where id = item.order_id for no key update;
  if not found or sale.status not in ('paid', 'void') then return; end if;
  perform 1 from public.outlets where id = sale.outlet_id for no key update;
  select * into applied from public.ingredient_sale_items where item_id = item.id;
  q := item.quantity::numeric;
  if found then
    if applied.quantity <> q or applied.product_id <> item.product_id or applied.order_id <> item.order_id then raise exception 'PAID_RECIPE_ITEM_IMMUTABLE'; end if;
    if sale.status = 'void' and not applied.reversed then
      for c in select value from jsonb_array_elements(applied.components) loop
        perform public.apply_ingredient_movement(sale.outlet_id, c->>'ingredient_id', 'void', item.id,
          (c->>'quantity')::numeric * applied.quantity, (c->>'unit_cost')::numeric, sale.updated_at);
      end loop;
      update public.ingredient_sale_items set reversed = true where item_id = item.id;
    end if;
    return;
  end if;
  if sale.status <> 'paid' then return; end if;
  if q is null or not (q > 0 and q < 1e12) then raise exception 'INVALID_SALE_QUANTITY'; end if;
  select * into recipe from public.inventory_recipe_versions where product_id = item.product_id and outlet_id = sale.outlet_id
    and effective_from <= coalesce(sale.paid_at, sale.created_at) order by effective_from desc, id desc limit 1;
  lines := coalesce(recipe.components, '[]');
  for c in select value from jsonb_array_elements(lines) loop
    perform public.apply_ingredient_movement(sale.outlet_id, c->>'ingredient_id', 'sale', item.id,
      -(c->>'quantity')::numeric * q, (c->>'unit_cost')::numeric, coalesce(sale.paid_at, sale.created_at));
  end loop;
  insert into public.ingredient_sale_items(item_id, order_id, outlet_id, product_id, quantity, components)
    values(item.id, sale.id, sale.outlet_id, item.product_id, q, lines);
end; $$;
create or replace function public.sync_ingredient_sale_item()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.reconcile_ingredient_sale_item(new.id);
  return new;
end; $$;
create or replace function public.sync_ingredient_order_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare item_id text;
begin
  for item_id in select id from public.order_items where order_id = new.id order by id loop
    perform public.reconcile_ingredient_sale_item(item_id);
  end loop;
  return new;
end; $$;
drop trigger if exists sync_ingredient_sale_item on public.order_items;
create trigger sync_ingredient_sale_item after insert or update on public.order_items for each row execute function public.sync_ingredient_sale_item();
drop trigger if exists sync_ingredient_order_status on public.orders;
create trigger sync_ingredient_order_status after update of status on public.orders for each row execute function public.sync_ingredient_order_status();

create or replace function public.guard_applied_ingredient_item()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists(select 1 from public.ingredient_sale_items where item_id = old.id) then
    if tg_op = 'DELETE' then raise exception 'PAID_RECIPE_ITEM_IMMUTABLE'; end if;
    if new.id is distinct from old.id or new.order_id is distinct from old.order_id
        or new.product_id is distinct from old.product_id or new.quantity::numeric is distinct from old.quantity::numeric then
      raise exception 'PAID_RECIPE_ITEM_IMMUTABLE';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end; $$;
drop trigger if exists guard_applied_ingredient_item on public.order_items;
create trigger guard_applied_ingredient_item before update or delete on public.order_items for each row execute function public.guard_applied_ingredient_item();

-- Stale devices must not reopen a void whose ingredients were restored, or
-- move a posted order into a different outlet while retaining its receipt.
create or replace function public.guard_ingredient_order()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists(select 1 from public.ingredient_sale_items where order_id = old.id) then
    if new.id is distinct from old.id or new.outlet_id is distinct from old.outlet_id
        or new.status not in ('paid', 'void') or new.status is null
        or (old.status = 'void' and new.status is distinct from 'void') then
      raise exception 'POSTED_INVENTORY_ORDER_IMMUTABLE';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists guard_ingredient_order on public.orders;
create trigger guard_ingredient_order before update on public.orders for each row execute function public.guard_ingredient_order();

create or replace function public.record_internal_material_usage(p_id text, p_outlet_id text, p_purpose text,
  p_items jsonb, p_occurred_at timestamptz, p_note text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare c jsonb; r jsonb; product public.products%rowtype; recipe public.inventory_recipe_versions%rowtype;
  q numeric; cost numeric; total numeric := 0; normalized jsonb := '[]'; untracked boolean := false; seen text[] := '{}';
  previous public.internal_material_usage%rowtype; fingerprint text := md5(p_purpose || p_items::text || extract(epoch from p_occurred_at)::text || coalesce(p_note, ''));
begin
  if auth.uid() is null or not public.current_user_has_outlet(p_outlet_id) then raise exception 'OWNER_ACCESS_REQUIRED'; end if;
  if not public.current_user_has_cloud_outlet(p_outlet_id) then raise exception 'CLOUD_REQUIRED'; end if;
  if p_id is null or p_purpose is null or p_purpose not in ('rnd', 'personal', 'waste')
      or p_occurred_at is null or p_occurred_at > now() + interval '5 minutes'
      or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200 then raise exception 'INVALID_INTERNAL_USAGE'; end if;
  perform 1 from public.outlets where id = p_outlet_id for no key update;
  select * into previous from public.internal_material_usage where id = p_id;
  if found then
    if previous.outlet_id <> p_outlet_id or previous.request_hash <> fingerprint then raise exception 'USAGE_ID_CONFLICT'; end if;
    return true;
  end if;
  for c in select value from jsonb_array_elements(p_items) loop
    select * into recipe from public.inventory_recipe_versions where product_id = c->>'product_id' and outlet_id = p_outlet_id
      and effective_from <= p_occurred_at order by effective_from desc, id desc limit 1;
    select * into product from public.products where id = c->>'product_id' and outlet_id = p_outlet_id;
    if not found then
      -- A queued usage made before deletion must still consume its snapshot.
      if recipe.id is null or exists(select 1 from public.sync_tombstones where entity_type = 'product'
          and record_id = recipe.product_id and deleted_at <= p_occurred_at) then raise exception 'INVALID_USAGE_PRODUCT'; end if;
      product.id := recipe.product_id; product.name := recipe.product_name; product.cogs := recipe.cogs::text;
      product.track_stock := false;
    end if;
    if product.id = any(seen) then raise exception 'INVALID_USAGE_PRODUCT'; end if;
    seen := array_append(seen, product.id);
    q := (c->>'quantity')::numeric;
    if q is null or not (q > 0 and q < 1e12) then raise exception 'INVALID_USAGE_QUANTITY'; end if;
    cost := coalesce(recipe.cogs, nullif(product.cogs, '')::numeric, 0);
    if coalesce(recipe.has_untracked_materials, true) then untracked := true; end if;
    -- Aggregate variants in the client so each product occurs once per usage.
    for r in select value from jsonb_array_elements(coalesce(recipe.components, '[]')) loop
      perform public.apply_ingredient_movement(p_outlet_id, r->>'ingredient_id', 'internal', jsonb_build_array(p_id, product.id)::text,
        -(r->>'quantity')::numeric * q, (r->>'unit_cost')::numeric, p_occurred_at);
    end loop;
    normalized := normalized || jsonb_build_array(jsonb_build_object('product_id', product.id, 'name', product.name, 'quantity', q, 'unit_cogs', cost));
    total := total + cost * q;
    if product.track_stock then
      update public.products set stock = greatest(0, coalesce(nullif(stock, '')::numeric, 0) - q)::text,
        updated_at = clock_timestamp() where id = product.id;
    end if;
  end loop;
  insert into public.internal_material_usage(id, outlet_id, purpose, occurred_at, note, items, total_cogs, request_hash, has_untracked_materials)
    values(p_id, p_outlet_id, p_purpose, p_occurred_at, p_note, normalized, total, fingerprint, untracked);
  insert into public.expenses(id, outlet_id, category, description, amount, occurred_at)
    values('internal:' || p_id, p_outlet_id, case p_purpose when 'rnd' then 'R&D / Kalibrasi' when 'personal' then 'Pemakaian pribadi' else 'Bahan terbuang' end,
      coalesce(p_note, 'Pemakaian bahan tanpa pembayaran'), total::text, p_occurred_at);
  return true;
end; $$;

-- The expense is the financial projection of a usage receipt, not a second
-- editable expense. Identical old-client sync upserts remain compatible.
create or replace function public.guard_internal_usage_expense()
returns trigger language plpgsql security definer set search_path = public as $$
declare receipt public.internal_material_usage%rowtype;
begin
  if tg_op <> 'INSERT' and exists(select 1 from public.internal_material_usage where 'internal:' || id = old.id) then
    if tg_op = 'DELETE' then raise exception 'INTERNAL_USAGE_EXPENSE_IMMUTABLE'; end if;
    if new.id is distinct from old.id or new.outlet_id is distinct from old.outlet_id
        or new.amount::numeric is distinct from old.amount::numeric
        or new.category is distinct from old.category or new.description is distinct from old.description
        or new.occurred_at is distinct from old.occurred_at then
      raise exception 'INTERNAL_USAGE_EXPENSE_IMMUTABLE';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if new.id like 'internal:%' then
    select * into receipt from public.internal_material_usage where 'internal:' || id = new.id;
    if not found or receipt.outlet_id <> new.outlet_id or receipt.total_cogs <> new.amount::numeric
        or receipt.occurred_at <> new.occurred_at then raise exception 'INVALID_INTERNAL_USAGE_EXPENSE'; end if;
  end if;
  return new;
end; $$;
drop trigger if exists guard_internal_usage_expense on public.expenses;
create trigger guard_internal_usage_expense before insert or update or delete on public.expenses
  for each row execute function public.guard_internal_usage_expense();

create or replace function public.guard_internal_usage_tombstone()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.entity_type = 'expense' and exists(select 1 from public.internal_material_usage where 'internal:' || id = new.record_id) then
    raise exception 'INTERNAL_USAGE_EXPENSE_IMMUTABLE';
  end if;
  return new;
end; $$;
drop trigger if exists guard_internal_usage_tombstone on public.sync_tombstones;
create trigger guard_internal_usage_tombstone before insert or update on public.sync_tombstones
  for each row execute function public.guard_internal_usage_tombstone();

-- No helper may be invoked directly using an authenticated/anon API key.
revoke all on function public.snapshot_inventory_recipe(text), public.refresh_inventory_recipe_costs(text),
  public.apply_ingredient_movement(text,text,text,text,numeric,numeric,timestamptz),
  public.reconcile_ingredient_sale_item(text), public.sync_ingredient_sale_item(), public.sync_ingredient_order_status()
  , public.guard_applied_ingredient_item()
  , public.validate_inventory_component_scope()
  , public.guard_internal_usage_expense()
  , public.guard_ingredient_order()
  , public.guard_internal_usage_tombstone()
  from public, anon, authenticated;
revoke all on function public.save_owner_ingredient(text,text,text,text), public.save_owner_product_with_costing(jsonb,jsonb,timestamptz,bigint),
  public.record_ingredient_purchase(text,text,jsonb,timestamptz,text), public.record_internal_material_usage(text,text,text,jsonb,timestamptz,text)
  from public, anon;
grant execute on function public.save_owner_ingredient(text,text,text,text), public.save_owner_product_with_costing(jsonb,jsonb,timestamptz,bigint),
  public.record_ingredient_purchase(text,text,jsonb,timestamptz,text), public.record_internal_material_usage(text,text,text,jsonb,timestamptz,text)
  to authenticated;

notify pgrst, 'reload schema';
