-- Owner-confirmed physical zero, with a durable inventory/expense receipt.
-- Pre-tracking sales correct opening inventory without inventing another cost.
alter table public.ingredient_movements drop constraint if exists ingredient_movements_source_type_check;
alter table public.ingredient_movements add constraint ingredient_movements_source_type_check
  check (source_type in ('purchase', 'sale', 'void', 'internal', 'depletion', 'manual_sale'));

create table if not exists public.ingredient_depletions (
  id text primary key,
  outlet_id text not null references public.outlets(id),
  ingredient_id text not null references public.ingredients(id),
  ingredient_name text not null,
  unit text not null check (unit in ('gram', 'milliliter', 'piece')),
  quantity numeric not null check (quantity > 0 and quantity < 1e12),
  unit_cost numeric not null check (unit_cost >= 0 and unit_cost < 1e12),
  total_cost numeric not null check (total_cost = quantity * unit_cost),
  purpose text not null check (purpose in ('waste', 'personal', 'pre_tracking_sales')),
  note text,
  expected_updated_at timestamptz not null,
  request_hash text not null,
  confirmed_by uuid not null,
  occurred_at timestamptz not null default clock_timestamp()
);
create index if not exists ingredient_depletions_outlet_date
  on public.ingredient_depletions(outlet_id, occurred_at);
alter table public.ingredient_depletions enable row level security;
revoke all on public.ingredient_depletions from public, anon, authenticated;
grant select on public.ingredient_depletions to authenticated;
drop policy if exists inventory_owner_read on public.ingredient_depletions;
create policy inventory_owner_read on public.ingredient_depletions for select to authenticated
  using (public.current_user_has_cloud_outlet(outlet_id));

create or replace function public.guard_ingredient_depletion_expense()
returns trigger language plpgsql security definer set search_path = public as $$
declare receipt public.ingredient_depletions%rowtype;
begin
  if tg_op <> 'INSERT' and exists (
      select 1 from public.ingredient_depletions where 'depletion:' || id = old.id) then
    if tg_op = 'DELETE' then raise exception 'INGREDIENT_DEPLETION_EXPENSE_IMMUTABLE'; end if;
    if new.id is distinct from old.id or new.outlet_id is distinct from old.outlet_id
        or new.amount::numeric is distinct from old.amount::numeric
        or new.category is distinct from old.category or new.description is distinct from old.description
        or new.occurred_at is distinct from old.occurred_at then
      raise exception 'INGREDIENT_DEPLETION_EXPENSE_IMMUTABLE';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if new.id like 'depletion:%' then
    select * into receipt from public.ingredient_depletions where 'depletion:' || id = new.id;
    if not found or receipt.purpose not in ('waste', 'personal') or receipt.outlet_id <> new.outlet_id
        or receipt.total_cost is distinct from new.amount::numeric
        or receipt.occurred_at is distinct from new.occurred_at
        or new.category is distinct from (case receipt.purpose when 'personal' then 'Pemakaian pribadi' else 'Bahan habis / selisih stok' end)
        or new.description is distinct from ('Bahan habis: ' || receipt.ingredient_name
          || case when receipt.note is null then '' else ' — ' || receipt.note end) then
      raise exception 'INVALID_INGREDIENT_DEPLETION_EXPENSE';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists guard_ingredient_depletion_expense on public.expenses;
create trigger guard_ingredient_depletion_expense before insert or update or delete on public.expenses
  for each row execute function public.guard_ingredient_depletion_expense();

create or replace function public.guard_ingredient_depletion_tombstone()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.entity_type = 'expense' and exists (
      select 1 from public.ingredient_depletions where 'depletion:' || id = new.record_id) then
    raise exception 'INGREDIENT_DEPLETION_EXPENSE_IMMUTABLE';
  end if;
  return new;
end; $$;
drop trigger if exists guard_ingredient_depletion_tombstone on public.sync_tombstones;
create trigger guard_ingredient_depletion_tombstone before insert or update on public.sync_tombstones
  for each row execute function public.guard_ingredient_depletion_tombstone();

create or replace function public.confirm_owner_ingredient_empty(
  p_id text, p_outlet_id text, p_ingredient_id text, p_purpose text,
  p_expected_updated_at timestamptz, p_sync_confirmed boolean default false, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare ing public.ingredients%rowtype; receipt public.ingredient_depletions%rowtype;
  recorded_at timestamptz; cost numeric; normalized_note text := nullif(btrim(p_note), '');
  fingerprint text;
begin
  if auth.uid() is null or not public.current_user_has_outlet(p_outlet_id) then
    raise exception 'OWNER_ACCESS_REQUIRED';
  end if;
  if not public.current_user_has_cloud_outlet(p_outlet_id) then raise exception 'CLOUD_REQUIRED'; end if;
  if p_id is null or length(btrim(p_id)) not between 1 and 200
      or p_ingredient_id is null or p_expected_updated_at is null
      or p_purpose is null or p_purpose not in ('waste', 'personal', 'pre_tracking_sales')
      or coalesce(length(normalized_note), 0) > 1000 then raise exception 'INVALID_INGREDIENT_DEPLETION'; end if;
  if p_sync_confirmed is distinct from true then raise exception 'INVENTORY_SYNC_CONFIRMATION_REQUIRED'; end if;
  fingerprint := md5(jsonb_build_array(p_ingredient_id, p_purpose,
      extract(epoch from p_expected_updated_at), normalized_note)::text);
  -- Same ordering as purchases, recipe saves and consumption: outlet, then ingredient.
  perform 1 from public.outlets where id = p_outlet_id for no key update;
  select * into receipt from public.ingredient_depletions where id = p_id;
  if found then
    if receipt.outlet_id <> p_outlet_id or receipt.request_hash <> fingerprint then
      raise exception 'DEPLETION_ID_CONFLICT';
    end if;
    return jsonb_build_object('id', receipt.id, 'quantity', receipt.quantity,
      'total_cost', receipt.total_cost, 'expense_created', receipt.purpose <> 'pre_tracking_sales');
  end if;
  select * into ing from public.ingredients where id = p_ingredient_id and outlet_id = p_outlet_id for update;
  if not found then raise exception 'INVALID_INGREDIENT'; end if;
  if ing.updated_at is distinct from p_expected_updated_at then raise exception 'INGREDIENT_STOCK_CHANGED_RELOAD'; end if;
  if ing.quantity <= 0 then raise exception 'INGREDIENT_ALREADY_EMPTY'; end if;
  recorded_at := clock_timestamp();
  cost := ing.quantity * ing.unit_cost;
  insert into public.ingredient_depletions(id, outlet_id, ingredient_id, ingredient_name, unit,
      quantity, unit_cost, total_cost, purpose, note, expected_updated_at, request_hash, confirmed_by, occurred_at)
    values(p_id, p_outlet_id, ing.id, ing.name, ing.unit, ing.quantity, ing.unit_cost, cost,
      p_purpose, normalized_note, p_expected_updated_at, fingerprint, auth.uid(), recorded_at);
  perform public.apply_ingredient_movement(p_outlet_id, ing.id, 'depletion', p_id,
    -ing.quantity, ing.unit_cost, recorded_at);
  if p_purpose <> 'pre_tracking_sales' then
    insert into public.expenses(id, outlet_id, category, description, amount, occurred_at)
      values('depletion:' || p_id, p_outlet_id,
        case p_purpose when 'personal' then 'Pemakaian pribadi' else 'Bahan habis / selisih stok' end,
        'Bahan habis: ' || ing.name || case when normalized_note is null then '' else ' — ' || normalized_note end,
        cost::text, recorded_at);
  end if;
  return jsonb_build_object('id', p_id, 'quantity', ing.quantity,
    'total_cost', cost, 'expense_created', p_purpose <> 'pre_tracking_sales');
end; $$;
revoke all on function public.guard_ingredient_depletion_expense(), public.guard_ingredient_depletion_tombstone()
  from public, anon, authenticated;
revoke all on function public.confirm_owner_ingredient_empty(text,text,text,text,timestamptz,boolean,text)
  from public, anon;
grant execute on function public.confirm_owner_ingredient_empty(text,text,text,text,timestamptz,boolean,text)
  to authenticated;

-- Explicit manual stock correction for sales made before ingredient tracking.
-- Existing sale revenue/HPP and finished-product stock must not be charged twice.
alter table public.internal_material_usage drop constraint if exists internal_material_usage_purpose_check;
alter table public.internal_material_usage add constraint internal_material_usage_purpose_check
  check (purpose in ('rnd', 'personal', 'waste', 'pre_tracking_sales'));

create or replace function public.record_previous_sale_material_usage(
  p_id text, p_outlet_id text, p_items jsonb, p_occurred_at timestamptz,
  p_untracked_confirmed boolean default false, p_note text default null
) returns boolean language plpgsql security definer set search_path = public as $$
declare c jsonb; r jsonb; recipe public.inventory_recipe_versions%rowtype;
  product public.products%rowtype; previous public.internal_material_usage%rowtype;
  q numeric; total numeric := 0; normalized jsonb := '[]'; seen text[] := '{}';
  untracked boolean := false; normalized_note text := nullif(btrim(p_note), ''); fingerprint text;
begin
  if auth.uid() is null or not public.current_user_has_outlet(p_outlet_id) then raise exception 'OWNER_ACCESS_REQUIRED'; end if;
  if not public.current_user_has_cloud_outlet(p_outlet_id) then raise exception 'CLOUD_REQUIRED'; end if;
  if p_id is null or length(btrim(p_id)) not between 1 and 200
      or p_occurred_at is null or p_occurred_at > now() + interval '5 minutes'
      or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200
      or coalesce(length(normalized_note),0) > 1000 then raise exception 'INVALID_PREVIOUS_SALE_USAGE'; end if;
  if p_untracked_confirmed is distinct from true then raise exception 'PREVIOUS_SALE_CONFIRMATION_REQUIRED'; end if;
  fingerprint := md5(jsonb_build_array('pre_tracking_sales',p_items,
      extract(epoch from p_occurred_at),normalized_note)::text);
  perform 1 from public.outlets where id = p_outlet_id for no key update;
  select * into previous from public.internal_material_usage where id = p_id;
  if found then
    if previous.outlet_id <> p_outlet_id or previous.request_hash <> fingerprint then raise exception 'USAGE_ID_CONFLICT'; end if;
    return true;
  end if;
  for c in select value from jsonb_array_elements(p_items) loop
    select * into product from public.products where id = c->>'product_id' and outlet_id = p_outlet_id;
    if not found or product.id = any(seen) then raise exception 'INVALID_USAGE_PRODUCT'; end if;
    seen := array_append(seen,product.id);
    -- Deliberately use the current linked recipe, even when the sale predates it.
    select * into recipe from public.inventory_recipe_versions
      where product_id = product.id and outlet_id = p_outlet_id order by effective_from desc,id desc limit 1;
    if not found or jsonb_array_length(recipe.components) = 0 then raise exception 'LINKED_RECIPE_REQUIRED'; end if;
    q := (c->>'quantity')::numeric;
    if q is null or not (q > 0 and q < 1e12) then raise exception 'INVALID_USAGE_QUANTITY'; end if;
    untracked := untracked or recipe.has_untracked_materials;
    for r in select value from jsonb_array_elements(recipe.components) loop
      perform public.apply_ingredient_movement(p_outlet_id,r->>'ingredient_id','manual_sale',
        jsonb_build_array(p_id,product.id)::text,-(r->>'quantity')::numeric*q,
        (r->>'unit_cost')::numeric,p_occurred_at);
    end loop;
    normalized := normalized || jsonb_build_array(jsonb_build_object('product_id',product.id,
      'name',product.name,'quantity',q,'unit_cogs',recipe.cogs,'recipe_version_id',recipe.id));
    total := total + recipe.cogs*q;
  end loop;
  insert into public.internal_material_usage(id,outlet_id,purpose,occurred_at,note,items,total_cogs,request_hash,has_untracked_materials)
    values(p_id,p_outlet_id,'pre_tracking_sales',p_occurred_at,normalized_note,normalized,total,fingerprint,untracked);
  return true;
end; $$;

-- A historical stock adjustment is not an additional operating expense.
create or replace function public.guard_internal_usage_expense()
returns trigger language plpgsql security definer set search_path = public as $$
declare receipt public.internal_material_usage%rowtype;
begin
  if tg_op <> 'INSERT' and exists(select 1 from public.internal_material_usage where 'internal:' || id = old.id) then
    if tg_op = 'DELETE' then raise exception 'INTERNAL_USAGE_EXPENSE_IMMUTABLE'; end if;
    if new.id is distinct from old.id or new.outlet_id is distinct from old.outlet_id
        or new.amount::numeric is distinct from old.amount::numeric
        or new.category is distinct from old.category or new.description is distinct from old.description
        or new.occurred_at is distinct from old.occurred_at then raise exception 'INTERNAL_USAGE_EXPENSE_IMMUTABLE'; end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if new.id like 'internal:%' then
    select * into receipt from public.internal_material_usage where 'internal:' || id = new.id;
    if not found or receipt.purpose = 'pre_tracking_sales' or receipt.outlet_id <> new.outlet_id
        or receipt.total_cogs <> new.amount::numeric or receipt.occurred_at <> new.occurred_at then
      raise exception 'INVALID_INTERNAL_USAGE_EXPENSE';
    end if;
  end if;
  return new;
end; $$;
revoke all on function public.record_previous_sale_material_usage(text,text,jsonb,timestamptz,boolean,text) from public,anon;
grant execute on function public.record_previous_sale_material_usage(text,text,jsonb,timestamptz,boolean,text) to authenticated;
notify pgrst, 'reload schema';
