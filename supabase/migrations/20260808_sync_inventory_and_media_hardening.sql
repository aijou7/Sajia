-- Multi-device sync hardening for Sajia.

create or replace function enforce_owner_outlet_plan_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  request_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    auth.role()::text,
    ''
  );
  normalized_email text := lower(trim(coalesce(new.owner_email, auth.jwt() ->> 'email', '')));
begin
  if request_role = 'authenticated' and normalized_email <> '' then
    if exists (
      select 1 from outlets
      where lower(trim(coalesce(owner_email, ''))) = normalized_email
    ) and not exists (
      select 1 from outlets
      where lower(trim(coalesce(owner_email, ''))) = normalized_email
        and upper(trim(coalesce(license_key, ''))) like 'PRO%'
    ) then
      raise exception 'SAJIA_PRO_REQUIRED_FOR_ADDITIONAL_OUTLET'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_owner_outlet_plan_before_insert on outlets;
create trigger enforce_owner_outlet_plan_before_insert
before insert on outlets
for each row execute function enforce_owner_outlet_plan_on_insert();

revoke all on function enforce_owner_outlet_plan_on_insert() from public;

create table if not exists sync_tombstones (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references outlets(id) on delete cascade,
  entity_type text not null check (entity_type in ('product', 'expense')),
  record_id text not null,
  deleted_at timestamptz not null default now(),
  unique (entity_type, record_id)
);

create index if not exists sync_tombstones_outlet_deleted_idx
  on sync_tombstones(outlet_id, deleted_at desc);

alter table sync_tombstones enable row level security;
grant select, insert, update on sync_tombstones to authenticated;

drop policy if exists owner_scope_sync_tombstones on sync_tombstones;
create policy owner_scope_sync_tombstones on sync_tombstones
for all to authenticated
using (current_user_has_outlet(outlet_id))
with check (current_user_has_outlet(outlet_id));

create table if not exists applied_stock_sales (
  order_id text primary key references orders(id) on delete cascade,
  outlet_id text not null references outlets(id) on delete cascade,
  applied_at timestamptz not null default now()
);

alter table applied_stock_sales enable row level security;
revoke all on table applied_stock_sales from anon, authenticated;

create or replace function set_product_stock(
  p_product_id text,
  p_stock numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_outlet_id text;
begin
  if p_stock < 0 then
    raise exception 'INVALID_STOCK';
  end if;

  select outlet_id into target_outlet_id
  from products
  where id = p_product_id;

  if target_outlet_id is null or not current_user_has_outlet(target_outlet_id) then
    raise exception 'OUTLET_ACCESS_REQUIRED';
  end if;

  update products
  set stock = p_stock::text,
      updated_at = now()
  where id = p_product_id;
  return true;
end;
$$;

create or replace function apply_order_stock_sale(p_order_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_outlet_id text;
  inserted_rows integer;
begin
  select outlet_id into target_outlet_id
  from orders
  where id = p_order_id and status = 'paid';

  if target_outlet_id is null or not current_user_has_outlet(target_outlet_id) then
    raise exception 'ORDER_ACCESS_REQUIRED';
  end if;

  insert into applied_stock_sales(order_id, outlet_id)
  values (p_order_id, target_outlet_id)
  on conflict (order_id) do nothing;
  get diagnostics inserted_rows = row_count;
  if inserted_rows = 0 then
    return true;
  end if;

  with sold as (
    select product_id,
      sum(coalesce(nullif(quantity, '')::numeric, 0)) as quantity
    from order_items
    where order_id = p_order_id
    group by product_id
  )
  update products product
  set stock = greatest(
        0,
        coalesce(nullif(product.stock, '')::numeric, 0) - sold.quantity
      )::text,
      updated_at = now()
  from sold
  where product.id = sold.product_id
    and product.outlet_id = target_outlet_id
    and product.track_stock = true;

  return true;
end;
$$;

revoke all on function set_product_stock(text, numeric) from public;
revoke all on function apply_order_stock_sale(text) from public;
grant execute on function set_product_stock(text, numeric) to authenticated;
grant execute on function apply_order_stock_sale(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists product_images_owner_insert on storage.objects;
create policy product_images_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'product-images'
  and current_user_has_outlet((storage.foldername(name))[1])
);

drop policy if exists product_images_owner_update on storage.objects;
create policy product_images_owner_update on storage.objects
for update to authenticated
using (
  bucket_id = 'product-images'
  and current_user_has_outlet((storage.foldername(name))[1])
)
with check (
  bucket_id = 'product-images'
  and current_user_has_outlet((storage.foldername(name))[1])
);

drop policy if exists product_images_owner_delete on storage.objects;
create policy product_images_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'product-images'
  and current_user_has_outlet((storage.foldername(name))[1])
);
