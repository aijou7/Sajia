-- Run through scripts/verify_ingredient_inventory.cjs in a disposable DB.
create function public.test_assert(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %', message; end if; end $$;
create function public.test_reject(statement text, expected text) returns void language plpgsql as $$
declare caught text; begin
  begin execute statement; exception when others then caught := sqlerrm; end;
  if caught is null or position(expected in caught) = 0 then raise exception 'Expected error %, got %', expected, caught; end if;
end $$;
insert into public.outlets(id,name,license_key) values('inventory-a','A','PRO-A'),('inventory-b','B','PRO-B');
insert into public.users(id,name,pin,role,outlet_id) values('cashier-a','Owner','123456','owner','inventory-a');
insert into public.categories(id,outlet_id,name) values('cat-a','inventory-a','Kopi');
select public.save_owner_ingredient('beans','inventory-a','Beans','gram');
select public.save_owner_ingredient('milk','inventory-a','Susu','milliliter');
select public.record_ingredient_purchase('buy-a','inventory-a',
  '[{"ingredient_id":"beans","quantity":1,"unit":"kilogram","price":190000},{"ingredient_id":"milk","quantity":1,"unit":"liter","price":23000}]', current_date::timestamptz);
select public.record_ingredient_purchase('buy-a','inventory-a',
  '[{"ingredient_id":"beans","quantity":1,"unit":"kilogram","price":190000},{"ingredient_id":"milk","quantity":1,"unit":"liter","price":23000}]', current_date::timestamptz);
select public.test_assert((select quantity=1000 and unit_cost=190 from public.ingredients where id='beans'), 'kg conversion, unit cost, purchase retry');
select public.test_assert((select quantity=1000 and unit_cost=23 from public.ingredients where id='milk'), 'liter conversion');
select public.test_assert((select count(*)=0 from public.expenses), 'purchase is not operating expense');
select set_config('test.cloud', 'false', false);
select public.test_reject($q$select public.save_owner_ingredient('free','inventory-a','Free','gram')$q$, 'CLOUD_REQUIRED');
select public.test_reject($q$select public.record_ingredient_purchase('free-buy','inventory-a','[{"ingredient_id":"beans","quantity":1,"unit":"gram","price":1}]', current_date::timestamptz)$q$, 'CLOUD_REQUIRED');
select public.test_reject($q$select public.record_internal_material_usage('free-use','inventory-a','rnd','[{"product_id":"coffee","quantity":1}]', current_timestamp)$q$, 'CLOUD_REQUIRED');
select set_config('test.cloud', 'true', false);
select public.save_owner_product_with_costing(
  '{"id":"coffee","outlet_id":"inventory-a","category_id":"cat-a","name":"Kopi Susu","price":"20000","base_cogs":"0","buffer_percent":5}',
  '[{"id":"c-beans","ingredient_id":"beans","recipe_quantity":18,"recipe_unit":"gram"},
    {"id":"c-extra","ingredient_id":"beans","recipe_quantity":2,"recipe_unit":"gram"},
    {"id":"c-milk","ingredient_id":"milk","recipe_quantity":120,"recipe_unit":"milliliter"}]');
select public.test_assert((select cogs='6888' from public.products where id='coffee'), 'authoritative price + 5% buffer');
select public.test_assert((select jsonb_array_length(components)=2 from public.inventory_recipe_versions where product_id='coffee' order by id desc limit 1), 'same ingredient aggregated');
insert into public.orders(id,outlet_id,order_number,type,status,cashier_id,cashier_name,paid_at)
  values('sale-a','inventory-a','1','takeaway','paid','cashier-a','Owner',clock_timestamp());
insert into public.order_items(id,order_id,product_id,product_name,unit_price,quantity,subtotal,unit_cogs)
  values('item-a','sale-a','coffee','Kopi Susu','20000','2','40000','6888');
update public.order_items set quantity='2', notes='retry' where id='item-a';
select public.test_assert((select quantity=960 from public.ingredients where id='beans'), 'sale consumes two portions once');
select public.test_assert((select quantity=760 from public.ingredients where id='milk'), 'sale milk once');
select public.test_reject($q$update public.order_items set quantity='3' where id='item-a'$q$, 'PAID_RECIPE_ITEM_IMMUTABLE');

-- Save a later recipe, then upload an offline order from the earlier version.
do $$ declare checkout timestamptz := clock_timestamp(); begin
  perform public.save_owner_product_with_costing(
    '{"id":"coffee","outlet_id":"inventory-a","category_id":"cat-a","name":"Kopi Susu","price":"20000","base_cogs":"0","buffer_percent":5}',
    '[{"id":"c-beans","ingredient_id":"beans","recipe_quantity":30,"recipe_unit":"gram"},
      {"id":"c-milk","ingredient_id":"milk","recipe_quantity":120,"recipe_unit":"milliliter"}]',
    (select updated_at from public.products where id='coffee'),
    (select revision from public.product_cost_profiles where product_id='coffee'));
  insert into public.orders(id,outlet_id,order_number,type,status,cashier_id,cashier_name,paid_at)
    values('offline-a','inventory-a','2','takeaway','paid','cashier-a','Owner',checkout);
  insert into public.order_items(id,order_id,product_id,product_name,unit_price,quantity,subtotal,unit_cogs)
    values('offline-item','offline-a','coffee','Kopi Susu','20000','1','20000','6888');
end $$;
select public.test_assert((select quantity=940 from public.ingredients where id='beans'), 'offline sale uses previous 20g recipe');
update public.orders set status='void', updated_at=clock_timestamp() where id='sale-a';
update public.orders set status='void', updated_at=clock_timestamp() where id='sale-a';
select public.test_assert((select quantity=980 from public.ingredients where id='beans'), 'void restores old recipe once');
select public.test_assert((select quantity=880 from public.ingredients where id='milk'), 'void milk restoration');
select public.test_reject($q$update public.orders set status='paid' where id='sale-a'$q$, 'POSTED_INVENTORY_ORDER_IMMUTABLE');
select public.test_reject($q$update public.orders set outlet_id='inventory-b' where id='offline-a'$q$, 'POSTED_INVENTORY_ORDER_IMMUTABLE');
select public.record_internal_material_usage('use-a','inventory-a','rnd','[{"product_id":"coffee","quantity":1}]', current_timestamp + interval '1 second');
select public.record_internal_material_usage('use-a','inventory-a','rnd','[{"product_id":"coffee","quantity":1}]', current_timestamp + interval '1 second');
select public.test_assert((select quantity=950 from public.ingredients where id='beans'), 'R&D consumes new recipe once');
select public.test_assert((select count(*)=1 and min(amount)='8883' from public.expenses), 'R&D HPP expense once');
select public.test_assert((select count(*)=2 from public.orders), 'R&D does not create a sale');
select public.test_assert((select count(*)=1 from public.internal_material_usage), 'usage receipt once');
update public.expenses set amount='8883.0' where id='internal:use-a';
select public.test_reject($q$update public.expenses set amount='1' where id='internal:use-a'$q$, 'INTERNAL_USAGE_EXPENSE_IMMUTABLE');
select public.test_reject($q$delete from public.expenses where id='internal:use-a'$q$, 'INTERNAL_USAGE_EXPENSE_IMMUTABLE');
select public.test_reject($q$insert into public.sync_tombstones(outlet_id,entity_type,record_id) values('inventory-a','expense','internal:use-a')$q$, 'INTERNAL_USAGE_EXPENSE_IMMUTABLE');
select public.test_reject($q$select public.record_internal_material_usage('use-a','inventory-a','rnd','[{"product_id":"coffee","quantity":2}]', current_timestamp + interval '1 second')$q$, 'USAGE_ID_CONFLICT');
select public.record_ingredient_purchase('buy-b','inventory-a','[{"ingredient_id":"beans","quantity":50,"unit":"gram","price":11000}]', current_date::timestamptz);
select public.test_assert((select quantity=1000 and unit_cost=191.5 from public.ingredients where id='beans'), 'weighted average purchase cost');
select public.test_assert((select count(*)=1 from public.expenses), 'second purchase still not an expense');
select public.test_assert((select unit_cogs='6888' from public.order_items where id='offline-item'), 'historical sale HPP unchanged');
select public.test_reject($q$select public.record_ingredient_purchase('bad-buy','inventory-a','[{"ingredient_id":"beans","quantity":1,"unit":"liter","price":1}]', current_date::timestamptz)$q$, 'INCOMPATIBLE_RECIPE_UNITS');
select public.test_assert((select quantity=1000 from public.ingredients where id='beans'), 'invalid purchase is atomic');
select public.test_reject($q$select public.save_owner_ingredient('foreign','inventory-b','Foreign','gram')$q$, 'OWNER_ACCESS_REQUIRED');
select public.test_assert(not has_function_privilege('authenticated','public.apply_ingredient_movement(text,text,text,text,numeric,numeric,timestamptz)','EXECUTE'), 'movement helper is private');
select public.test_assert(not has_function_privilege('authenticated','public.save_owner_product_costing_legacy(jsonb,jsonb,timestamptz,bigint)','EXECUTE'), 'legacy RPC cannot bypass new checks');
select public.test_assert(not has_function_privilege('anon','public.record_internal_material_usage(text,text,text,jsonb,timestamptz,text)','EXECUTE'), 'anonymous usage denied');
select public.test_assert(not has_table_privilege('authenticated','public.ingredients','UPDATE'), 'balances cannot be written directly');
select public.delete_owner_menu_entity('inventory-a','category','cat-a');
update public.categories set is_active=true where id='cat-a';
update public.products set category_id='cat-a' where id='coffee';
select public.test_assert((select not is_active and deleted_at is not null from public.categories where id='cat-a'), 'deleted category cannot reactivate');
select public.test_assert((select category_id is null from public.products where id='coffee'), 'stale category assignment cleared');
select public.delete_owner_menu_entity('inventory-a','product','coffee');
insert into public.products(id,outlet_id,name,price) values('coffee','inventory-a','Stale copy','20000');
select public.test_assert((select count(*)=0 from public.products where id='coffee'), 'deleted product cannot resurrect');
select public.test_assert((select count(*)=2 from public.order_items where product_id='coffee'), 'historical order items preserved');
select public.test_assert((select count(*)=0 from public.product_cost_components where product_id='coffee'), 'recipe removed with product');
-- Queued internal use survives menu deletion and still uses its old recipe.
select public.record_internal_material_usage('use-offline','inventory-a','personal','[{"product_id":"coffee","quantity":1}]',
  (select max(effective_from) from public.inventory_recipe_versions where product_id='coffee'));
select public.test_assert((select quantity=970 from public.ingredients where id='beans'), 'offline usage after deletion consumes saved recipe');
select public.test_reject($q$select public.record_internal_material_usage('use-deleted','inventory-a','personal','[{"product_id":"coffee","quantity":1}]',
  (select deleted_at from public.sync_tombstones where record_id='coffee'))$q$, 'INVALID_USAGE_PRODUCT');
