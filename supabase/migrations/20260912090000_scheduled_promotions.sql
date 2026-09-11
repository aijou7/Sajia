-- Owner-managed Happy Hour / scheduled menu prices.
--
-- A promotion is configured in the owner portal and read by cashier devices.
-- The cashier stores the normal unit price and per-item discount with every
-- order item, so historic receipts and reports never change when a schedule
-- is edited or deleted later.

create or replace function valid_scheduled_promotion_days(p_days jsonb)
returns boolean
language sql
immutable
as $$
  select case
    when p_days is null then false
    when jsonb_typeof(p_days) <> 'array' then false
    when jsonb_array_length(p_days) not between 1 and 7 then false
    else not exists (
      select 1
      from jsonb_array_elements_text(p_days) as day(value)
      where day.value !~ '^[1-7]$'
    )
    and (
      select count(*) = count(distinct day.value)
      from jsonb_array_elements_text(p_days) as day(value)
    )
  end;
$$;

create table if not exists scheduled_promotions (
  id text primary key,
  outlet_id text not null references outlets(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  start_time time not null,
  end_time time not null,
  active_days jsonb not null default '[1, 2, 3, 4, 5, 6, 7]'::jsonb,
  is_active boolean not null default true,
  priority integer not null default 0 check (priority between -1000 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_time > start_time),
  check (valid_scheduled_promotion_days(active_days))
);

create table if not exists scheduled_promotion_items (
  id text primary key,
  promotion_id text not null references scheduled_promotions(id) on delete cascade,
  product_id text not null references products(id) on delete cascade,
  promo_price numeric(14, 2) not null check (promo_price >= 0),
  created_at timestamptz not null default now(),
  unique (promotion_id, product_id)
);

create index if not exists idx_scheduled_promotions_outlet_active
  on scheduled_promotions(outlet_id, is_active, priority desc, updated_at desc);
create index if not exists idx_scheduled_promotion_items_product
  on scheduled_promotion_items(product_id);

alter table scheduled_promotions enable row level security;
alter table scheduled_promotion_items enable row level security;

revoke all on table scheduled_promotions, scheduled_promotion_items
from anon, authenticated;
grant select on table scheduled_promotions, scheduled_promotion_items to authenticated;

drop policy if exists owner_scope_scheduled_promotions on scheduled_promotions;
create policy owner_scope_scheduled_promotions on scheduled_promotions
for select to authenticated
using (current_user_has_outlet(outlet_id));

drop policy if exists owner_scope_scheduled_promotion_items on scheduled_promotion_items;
create policy owner_scope_scheduled_promotion_items on scheduled_promotion_items
for select to authenticated
using (
  exists (
    select 1
    from scheduled_promotions promotion
    where promotion.id = scheduled_promotion_items.promotion_id
      and current_user_has_outlet(promotion.outlet_id)
  )
);

-- The portal writes a schedule and all of its menu prices in one transaction.
-- Direct INSERT/UPDATE/DELETE remains unavailable to browser and mobile
-- clients, preventing a half-saved promo or an item from another outlet.
create or replace function upsert_scheduled_promotion(
  p_id text,
  p_outlet_id text,
  p_name text,
  p_start_time time,
  p_end_time time,
  p_active_days jsonb,
  p_is_active boolean,
  p_items jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_rows integer;
begin
  if auth.uid() is null or not current_user_has_outlet(p_outlet_id) then
    raise exception 'PROMOTION_ACCESS_DENIED';
  end if;

  if nullif(btrim(coalesce(p_id, '')), '') is null then
    raise exception 'PROMOTION_ID_REQUIRED';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 80 then
    raise exception 'PROMOTION_NAME_INVALID';
  end if;
  if p_start_time is null or p_end_time is null or p_end_time <= p_start_time then
    raise exception 'PROMOTION_TIME_RANGE_INVALID';
  end if;
  if coalesce(valid_scheduled_promotion_days(p_active_days), false) is not true then
    raise exception 'PROMOTION_DAYS_INVALID';
  end if;
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'PROMOTION_ITEMS_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as item(value)
    where nullif(btrim(coalesce(item.value ->> 'product_id', '')), '') is null
       or coalesce(item.value ->> 'promo_price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$'
  ) then
    raise exception 'PROMOTION_ITEM_INVALID';
  end if;

  if (
    select count(*) <> count(distinct item.value ->> 'product_id')
    from jsonb_array_elements(p_items) as item(value)
  ) then
    raise exception 'PROMOTION_PRODUCT_DUPLICATE';
  end if;

  -- Every selected menu must belong to the outlet, have a valid normal price,
  -- and receive a strictly lower (never stacked or price-increasing) price.
  if exists (
    select 1
    from jsonb_array_elements(p_items) as item(value)
    left join products product
      on product.id = item.value ->> 'product_id'
     and product.outlet_id = p_outlet_id
    where product.id is null
       or btrim(coalesce(product.price, '')) !~ '^[0-9]+(\.[0-9]{1,2})?$'
  ) then
    raise exception 'PROMOTION_PRODUCT_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as item(value)
    join products product
      on product.id = item.value ->> 'product_id'
     and product.outlet_id = p_outlet_id
    where (item.value ->> 'promo_price')::numeric >= product.price::numeric
  ) then
    raise exception 'PROMOTION_PRICE_NOT_LOWER';
  end if;

  insert into scheduled_promotions (
    id,
    outlet_id,
    name,
    start_time,
    end_time,
    active_days,
    is_active,
    updated_at
  )
  values (
    p_id,
    p_outlet_id,
    btrim(p_name),
    p_start_time,
    p_end_time,
    p_active_days,
    coalesce(p_is_active, true),
    now()
  )
  on conflict (id) do update
  set name = excluded.name,
      start_time = excluded.start_time,
      end_time = excluded.end_time,
      active_days = excluded.active_days,
      is_active = excluded.is_active,
      updated_at = now()
  where scheduled_promotions.outlet_id = excluded.outlet_id;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'PROMOTION_NOT_FOUND';
  end if;

  delete from scheduled_promotion_items where promotion_id = p_id;

  insert into scheduled_promotion_items (
    id,
    promotion_id,
    product_id,
    promo_price
  )
  select
    p_id || ':' || (item.value ->> 'product_id'),
    p_id,
    item.value ->> 'product_id',
    (item.value ->> 'promo_price')::numeric
  from jsonb_array_elements(p_items) as item(value);

  return p_id;
end;
$$;

create or replace function delete_scheduled_promotion(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_outlet_id text;
begin
  select outlet_id
    into target_outlet_id
  from scheduled_promotions
  where id = p_id;

  if target_outlet_id is null or not current_user_has_outlet(target_outlet_id) then
    raise exception 'PROMOTION_NOT_FOUND';
  end if;

  delete from scheduled_promotions where id = p_id;
end;
$$;

revoke all on function valid_scheduled_promotion_days(jsonb) from public;
revoke all on function upsert_scheduled_promotion(
  text, text, text, time, time, jsonb, boolean, jsonb
) from public, anon;
revoke all on function delete_scheduled_promotion(text) from public, anon;
grant execute on function upsert_scheduled_promotion(
  text, text, text, time, time, jsonb, boolean, jsonb
) to authenticated;
grant execute on function delete_scheduled_promotion(text) to authenticated;
