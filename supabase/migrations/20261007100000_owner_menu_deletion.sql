-- Delete menu data without deleting historical order-item snapshots.
alter table public.categories add column if not exists deleted_at timestamptz;
alter table public.sync_tombstones drop constraint if exists sync_tombstones_entity_type_check;
alter table public.sync_tombstones add constraint sync_tombstones_entity_type_check
  check (entity_type in ('product', 'category', 'expense', 'restaurant_table', 'user_outlet_access'));

create or replace function public.prevent_deleted_menu_resurrection()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.sync_tombstones
      where entity_type = case when tg_table_name = 'products' then 'product' else 'category' end
        and record_id = new.id and outlet_id = new.outlet_id) then
    if tg_table_name = 'products' or tg_op = 'INSERT' then return null; end if;
    new.is_active := false;
    new.deleted_at := coalesce(old.deleted_at, new.deleted_at, clock_timestamp());
  end if;
  if tg_table_name = 'products' then
    if exists (select 1 from public.sync_tombstones
        where entity_type = 'category' and record_id = new.category_id
          and outlet_id = new.outlet_id) then
      new.category_id := null;
    end if;
  end if;
  return new;
end; $$;
revoke all on function public.prevent_deleted_menu_resurrection() from public, anon, authenticated;
drop trigger if exists prevent_deleted_product_resurrection on public.products;
create trigger prevent_deleted_product_resurrection before insert or update on public.products
  for each row execute function public.prevent_deleted_menu_resurrection();
drop trigger if exists prevent_deleted_category_resurrection on public.categories;
create trigger prevent_deleted_category_resurrection before insert or update on public.categories
  for each row execute function public.prevent_deleted_menu_resurrection();

create or replace function public.delete_owner_menu_entity(p_outlet_id text, p_kind text, p_id text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.current_user_has_outlet(p_outlet_id) then
    raise exception 'OWNER_ACCESS_REQUIRED';
  end if;
  if p_kind not in ('product', 'category') or p_kind is null or p_id is null then
    raise exception 'INVALID_MENU_ENTITY';
  end if;
  perform 1 from public.outlets where id = p_outlet_id for no key update;
  if p_kind = 'product' then
    perform 1 from public.products where id = p_id and outlet_id = p_outlet_id for update;
  else
    perform 1 from public.categories where id = p_id and outlet_id = p_outlet_id for update;
  end if;
  if not found then
    return exists (select 1 from public.sync_tombstones
      where outlet_id = p_outlet_id and entity_type = p_kind and record_id = p_id);
  end if;
  insert into public.sync_tombstones(outlet_id, entity_type, record_id, deleted_at)
    values (p_outlet_id, p_kind, p_id, clock_timestamp())
    on conflict (entity_type, record_id) do update set deleted_at = clock_timestamp()
      where public.sync_tombstones.outlet_id = excluded.outlet_id;
  if p_kind = 'product' then
    delete from public.product_cost_components where product_id = p_id and outlet_id = p_outlet_id;
    delete from public.products where id = p_id and outlet_id = p_outlet_id;
  else
    update public.categories set is_active = false, deleted_at = clock_timestamp(),
      updated_at = clock_timestamp() where id = p_id and outlet_id = p_outlet_id;
    update public.products set category_id = null, updated_at = clock_timestamp()
      where category_id = p_id and outlet_id = p_outlet_id;
  end if;
  return true;
end; $$;
revoke all on function public.delete_owner_menu_entity(text, text, text) from public, anon;
grant execute on function public.delete_owner_menu_entity(text, text, text) to authenticated;
