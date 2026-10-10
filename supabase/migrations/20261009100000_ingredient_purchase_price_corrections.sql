-- Correct a price without creating another purchase, consuming stock twice,
-- or changing the original request fingerprint used by older clients.
create table if not exists public.ingredient_purchase_price_corrections (
  id text primary key,
  outlet_id text not null references public.outlets(id),
  purchase_id text not null references public.ingredient_purchases(id),
  revision bigint not null check (revision > 0),
  previous_items jsonb not null, corrected_items jsonb not null,
  previous_total numeric not null, total numeric not null,
  note text, request_hash text not null, corrected_by uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(purchase_id, revision)
);
create index if not exists purchase_price_corrections_outlet
  on public.ingredient_purchase_price_corrections(outlet_id);
create index if not exists ingredient_movements_valuation
  on public.ingredient_movements(outlet_id, ingredient_id, id);
alter table public.ingredient_purchase_price_corrections enable row level security;
revoke all on public.ingredient_purchase_price_corrections from public, anon, authenticated;
grant select on public.ingredient_purchase_price_corrections to authenticated;
drop policy if exists inventory_owner_read on public.ingredient_purchase_price_corrections;
create policy inventory_owner_read on public.ingredient_purchase_price_corrections
  for select to authenticated using (public.current_user_has_cloud_outlet(outlet_id));

-- Replay ONLY valuation in recording order, not occurred_at (purchases may be
-- backdated). Historical stock movements, sale HPP and expenses remain frozen.
-- Caller holds the outlet lock, also used by purchase/sale/internal-use RPCs.
create or replace function public.revalue_ingredient_purchase_cost(p_outlet_id text, p_ingredient_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  ing public.ingredients%rowtype; movement record; item jsonb;
  balance numeric := 0; average_cost numeric := 0; price numeric; bought numeric;
begin
  select * into ing from public.ingredients
    where id = p_ingredient_id and outlet_id = p_outlet_id for update;
  if not found then raise exception 'INVALID_PURCHASE_PRICE_CORRECTION'; end if;
  for movement in
    select m.id, m.source_type, m.quantity,
      coalesce(c.corrected_items, p.items) as purchase_items
    from public.ingredient_movements m
    left join public.ingredient_purchases p
      on m.source_type = 'purchase' and p.id = m.source_id and p.outlet_id = m.outlet_id
    left join lateral (
      select corrected_items from public.ingredient_purchase_price_corrections
      where purchase_id = p.id and outlet_id = p_outlet_id
      order by revision desc limit 1
    ) c on true
    where m.outlet_id = p_outlet_id and m.ingredient_id = p_ingredient_id
    order by m.id
  loop
    if movement.source_type = 'purchase' then
      select value into item from jsonb_array_elements(movement.purchase_items)
        where value->>'ingredient_id' = p_ingredient_id;
      bought := (item->>'quantity')::numeric * public.inventory_unit_factor(item->>'unit');
      price := (item->>'price')::numeric;
      if bought is null or bought is distinct from movement.quantity or bought <= 0
          or price is null or not (price >= 0 and price < 1e12) then
        raise exception 'INGREDIENT_LEDGER_REVIEW_REQUIRED';
      end if;
      average_cost := case when balance > 0 then
        (balance * average_cost + price) / (balance + bought) else price / bought end;
    end if;
    balance := balance + movement.quantity;
  end loop;
  if balance is distinct from ing.quantity then
    raise exception 'INGREDIENT_LEDGER_REVIEW_REQUIRED';
  end if;
  update public.ingredients set unit_cost = average_cost, updated_at = clock_timestamp()
    where id = p_ingredient_id and outlet_id = p_outlet_id;
end; $$;
revoke all on function public.revalue_ingredient_purchase_cost(text,text) from public, anon, authenticated;

create or replace function public.correct_ingredient_purchase_prices(
  p_id text, p_outlet_id text, p_purchase_id text, p_prices jsonb,
  p_expected_revision bigint, p_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  purchase public.ingredient_purchases%rowtype;
  previous public.ingredient_purchase_price_corrections%rowtype;
  current_items jsonb; corrected jsonb := '[]'; line jsonb; request_line jsonb;
  current_revision bigint := 0; current_total numeric; total numeric := 0;
  price numeric; seen text[] := '{}'; changed boolean := false;
  fingerprint text := md5(jsonb_build_object('outlet', p_outlet_id, 'purchase', p_purchase_id,
    'prices', p_prices, 'revision', p_expected_revision, 'note', p_note)::text);
begin
  if auth.uid() is null or not public.current_user_has_outlet(p_outlet_id) then
    raise exception 'OWNER_ACCESS_REQUIRED';
  end if;
  if not public.current_user_has_cloud_outlet(p_outlet_id) then raise exception 'CLOUD_REQUIRED'; end if;
  if p_id is null or length(p_id) not between 1 and 200
      or p_purchase_id is null or length(p_purchase_id) not between 1 and 200
      or p_expected_revision is null or p_expected_revision < 0
      or length(coalesce(p_note, '')) > 1000
      or jsonb_typeof(p_prices) is distinct from 'array' then
    raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
  end if;
  if jsonb_array_length(p_prices) not between 1 and 200 then
    raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
  end if;
  perform 1 from public.outlets where id = p_outlet_id for no key update;
  -- A lost-response retry must succeed even after another owner correction.
  select * into previous from public.ingredient_purchase_price_corrections where id = p_id;
  if found then
    if previous.outlet_id <> p_outlet_id or previous.purchase_id <> p_purchase_id
        or previous.request_hash <> fingerprint then raise exception 'PURCHASE_CORRECTION_ID_CONFLICT'; end if;
    return jsonb_build_object('id', previous.id, 'revision', previous.revision, 'total', previous.total);
  end if;
  select * into purchase from public.ingredient_purchases
    where id = p_purchase_id and outlet_id = p_outlet_id;
  if not found then raise exception 'INVALID_PURCHASE_PRICE_CORRECTION'; end if;
  select * into previous from public.ingredient_purchase_price_corrections
    where purchase_id = p_purchase_id and outlet_id = p_outlet_id order by revision desc limit 1;
  if found then
    current_revision := previous.revision;
    current_items := previous.corrected_items;
    current_total := previous.total;
  else
    current_items := purchase.items;
    current_total := purchase.total;
  end if;
  if p_expected_revision <> current_revision then raise exception 'PURCHASE_PRICE_CHANGED_RELOAD'; end if;
  if jsonb_array_length(p_prices) <> jsonb_array_length(current_items) then
    raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
  end if;
  for request_line in select value from jsonb_array_elements(p_prices) loop
    if jsonb_typeof(request_line) is distinct from 'object'
        or request_line->>'ingredient_id' is null
        or request_line->>'ingredient_id' = any(seen) then
      raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
    end if;
    -- The price-only contract cannot change stock quantity, unit, or identity.
    if (request_line - 'ingredient_id' - 'price') <> '{}'::jsonb then
      raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
    end if;
    seen := array_append(seen, request_line->>'ingredient_id');
    if not exists(select 1 from jsonb_array_elements(current_items)
        where value->>'ingredient_id' = request_line->>'ingredient_id') then
      raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
    end if;
    begin price := (request_line->>'price')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
    end;
    if price is null or not (price >= 0 and price < 1e12) then
      raise exception 'INVALID_PURCHASE_PRICE_CORRECTION';
    end if;
  end loop;
  for line in select value from jsonb_array_elements(current_items) loop
    select (value->>'price')::numeric into price from jsonb_array_elements(p_prices)
      where value->>'ingredient_id' = line->>'ingredient_id';
    changed := changed or price is distinct from (line->>'price')::numeric;
    total := total + price;
    corrected := corrected || jsonb_build_array(jsonb_set(line, '{price}', to_jsonb(price)));
  end loop;
  if not changed then raise exception 'PURCHASE_PRICES_UNCHANGED'; end if;
  insert into public.ingredient_purchase_price_corrections
    (id,outlet_id,purchase_id,revision,previous_items,corrected_items,previous_total,total,note,request_hash,corrected_by)
    values(p_id,p_outlet_id,p_purchase_id,current_revision+1,current_items,corrected,current_total,total,
      nullif(btrim(p_note), ''),fingerprint,auth.uid());
  for line in select value from jsonb_array_elements(corrected) order by value->>'ingredient_id' loop
    perform public.revalue_ingredient_purchase_cost(p_outlet_id, line->>'ingredient_id');
  end loop;
  perform public.refresh_inventory_recipe_costs(p_outlet_id);
  return jsonb_build_object('id', p_id, 'revision', current_revision+1, 'total', total);
end; $$;
revoke all on function public.correct_ingredient_purchase_prices(text,text,text,jsonb,bigint,text) from public, anon;
grant execute on function public.correct_ingredient_purchase_prices(text,text,text,jsonb,bigint,text) to authenticated;
notify pgrst, 'reload schema';
