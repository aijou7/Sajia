-- Owner web stock adjustments must not silently overwrite stock that changed
-- while a cashier device was syncing a sale or reversal. Keep the existing
-- set_product_stock(text, numeric) RPC for installed APK compatibility; the
-- web portal uses this compare-and-set RPC instead.
create or replace function set_owner_product_stock_if_current(
  p_product_id text,
  p_expected_stock numeric,
  p_new_stock numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_outlet_id text;
  current_stock numeric;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_expected_stock is null
      or p_new_stock is null
      or p_expected_stock < 0
      or p_new_stock < 0
      or p_expected_stock::text in ('NaN', 'Infinity', '-Infinity')
      or p_new_stock::text in ('NaN', 'Infinity', '-Infinity') then
    raise exception 'INVALID_STOCK';
  end if;

  select
    product.outlet_id,
    case
      when btrim(coalesce(product.stock, '')) ~ '^[0-9]+(\.[0-9]+)?$'
        then btrim(product.stock)::numeric
      else 0
    end
  into target_outlet_id, current_stock
  from products product
  where product.id = p_product_id
  for update;

  if target_outlet_id is null
      or not current_user_has_outlet(target_outlet_id) then
    raise exception 'OUTLET_ACCESS_REQUIRED';
  end if;

  if current_stock <> p_expected_stock then
    return jsonb_build_object(
      'applied', false,
      'current_stock', current_stock::text
    );
  end if;

  update products
  set stock = p_new_stock::text,
      updated_at = now()
  where id = p_product_id;

  return jsonb_build_object(
    'applied', true,
    'current_stock', p_new_stock::text
  );
end;
$$;

revoke all on function set_owner_product_stock_if_current(text, numeric)
  from public, anon;
grant execute on function set_owner_product_stock_if_current(text, numeric)
  to authenticated;
