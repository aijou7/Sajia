-- Uses the assertion helpers/fixtures from ingredient_inventory.sql.
select public.save_owner_ingredient('deplete-milk','inventory-a','Susu habis','milliliter');
select public.record_ingredient_purchase('deplete-buy','inventory-a',
  '[{"ingredient_id":"deplete-milk","quantity":1,"unit":"liter","price":23000}]', current_date::timestamptz);

do $$ declare original_time timestamptz; expenses_before bigint; orders_before bigint; result jsonb; begin
  select updated_at into original_time from public.ingredients where id='deplete-milk';
  select count(*) into expenses_before from public.expenses;
  select count(*) into orders_before from public.orders;
  result := public.confirm_owner_ingredient_empty('deplete-waste','inventory-a','deplete-milk','waste',original_time,true,'Susu rusak');
  perform public.test_assert(result->>'expense_created'='true' and (result->>'total_cost')::numeric=23000, 'waste valued at actual average cost: ' || result::text);
  perform public.test_assert((select quantity=0 and unit_cost=23 from public.ingredients where id='deplete-milk'), 'empty stock retains price for HPP');
  perform public.test_assert((select count(*)=expenses_before+1 from public.expenses), 'one waste expense');
  perform public.test_assert((select count(*)=orders_before from public.orders), 'no sale invented');
  perform public.test_assert((select count(*)=1 and min(quantity)=-1000 from public.ingredient_movements where source_type='depletion' and source_id='deplete-waste'), 'one inventory movement');
  -- A timeout retry after fresh stock arrived must return the original receipt.
  perform public.record_ingredient_purchase('deplete-rebuy','inventory-a',
    '[{"ingredient_id":"deplete-milk","quantity":0.5,"unit":"liter","price":12500}]', current_date::timestamptz);
  perform set_config('TimeZone','Asia/Makassar',true);
  perform public.confirm_owner_ingredient_empty('deplete-waste','inventory-a','deplete-milk','waste',original_time,true,'Susu rusak');
  perform public.test_assert((select quantity=500 and unit_cost=25 from public.ingredients where id='deplete-milk'), 'retry never consumes later purchase');
  perform public.test_assert((select count(*)=expenses_before+1 from public.expenses), 'retry never duplicates expense');
  perform public.test_reject(format('select public.confirm_owner_ingredient_empty(%L,%L,%L,%L,%L,true,%L)',
    'deplete-waste','inventory-a','deplete-milk','pre_tracking_sales',original_time,'Susu rusak'), 'DEPLETION_ID_CONFLICT');
  perform public.test_reject(format('select public.confirm_owner_ingredient_empty(%L,%L,%L,%L,%L,true,null)',
    'deplete-stale','inventory-a','deplete-milk','waste',original_time), 'INGREDIENT_STOCK_CHANGED_RELOAD');
  perform public.test_assert((select count(*)=0 from public.ingredient_depletions where id='deplete-stale'), 'stale stock rejected atomically');
  select updated_at into original_time from public.ingredients where id='deplete-milk';
  perform public.test_reject(format('select public.confirm_owner_ingredient_empty(%L,%L,%L,%L,%L,false,null)',
    'deplete-unsynced','inventory-a','deplete-milk','waste',original_time), 'INVENTORY_SYNC_CONFIRMATION_REQUIRED');
  perform public.confirm_owner_ingredient_empty('deplete-opening','inventory-a','deplete-milk','pre_tracking_sales',original_time,true,'Terjual sebelum resep terhubung');
  perform public.test_assert((select quantity=0 from public.ingredients where id='deplete-milk'), 'pre-tracking sales can start at zero');
  perform public.test_assert((select count(*)=expenses_before+1 from public.expenses), 'opening correction does not charge HPP twice');
  perform public.test_assert((select unit_cogs='6888' from public.order_items where id='offline-item'), 'past transaction HPP remains unchanged');
  select updated_at into original_time from public.ingredients where id='deplete-milk';
  perform public.test_reject(format('select public.confirm_owner_ingredient_empty(%L,%L,%L,%L,%L,true,null)',
    'deplete-again','inventory-a','deplete-milk','waste',original_time), 'INGREDIENT_ALREADY_EMPTY');
  perform public.test_reject(format('select public.confirm_owner_ingredient_empty(%L,%L,%L,%L,%L,true,null)',
    'deplete-bad','inventory-a','deplete-milk','other',original_time), 'INVALID_INGREDIENT_DEPLETION');
end $$;
-- Direct personal consumption of the remaining ingredient is an expense.
select public.record_ingredient_purchase('deplete-personal-buy','inventory-a',
  '[{"ingredient_id":"deplete-milk","quantity":100,"unit":"milliliter","price":2300}]',current_date::timestamptz);
select public.confirm_owner_ingredient_empty('deplete-personal','inventory-a','deplete-milk','personal',
  (select updated_at from public.ingredients where id='deplete-milk'),true,'Minum sendiri');
select public.test_assert((select quantity=0 from public.ingredients where id='deplete-milk'), 'personal stock zero');
select public.test_assert((select amount::numeric=2300 and category='Pemakaian pribadi' from public.expenses where id='depletion:deplete-personal'), 'personal remainder is operating expense');

-- A manual previous sale uses the CURRENT linked recipe even before tracking
-- began, without touching historical revenue, HPP or finished-product stock.
select public.save_owner_product_with_costing(
  '{"id":"history-latte","outlet_id":"inventory-a","name":"Latte lama","price":"20000","base_cogs":"0","buffer_percent":0,"track_stock":true,"stock":"100"}',
  '[{"id":"history-beans","ingredient_id":"beans","recipe_quantity":10,"recipe_unit":"gram"},
    {"id":"history-milk","ingredient_id":"milk","recipe_quantity":50,"recipe_unit":"milliliter"}]');
do $$ declare before_beans numeric; before_milk numeric; before_finished text; expenses_before bigint; orders_before bigint; begin
  select quantity into before_beans from public.ingredients where id='beans';
  select quantity into before_milk from public.ingredients where id='milk';
  select stock into before_finished from public.products where id='history-latte';
  select count(*) into expenses_before from public.expenses;
  select count(*) into orders_before from public.orders;
  perform public.record_previous_sale_material_usage('manual-history','inventory-a',
    '[{"product_id":"history-latte","quantity":3}]',current_date::timestamptz-interval '7 days',true,'Penjualan sebelum resep');
  perform public.record_previous_sale_material_usage('manual-history','inventory-a',
    '[{"product_id":"history-latte","quantity":3}]',current_date::timestamptz-interval '7 days',true,'Penjualan sebelum resep');
  perform public.test_assert((select quantity=before_beans-30 from public.ingredients where id='beans'), 'previous sale consumes current bean recipe once');
  perform public.test_assert((select quantity=before_milk-150 from public.ingredients where id='milk'), 'previous sale consumes milk recipe once');
  perform public.test_assert((select count(*)=expenses_before from public.expenses), 'previous sale never duplicates HPP expense');
  perform public.test_assert((select count(*)=orders_before from public.orders), 'previous sale never duplicates revenue');
  perform public.test_assert((select stock=before_finished from public.products where id='history-latte'), 'finished stock not charged twice');
  perform public.test_assert((select unit_cogs='6888' from public.order_items where id='offline-item'), 'previous sale does not rewrite historic HPP');
  perform public.test_reject($q$select public.record_previous_sale_material_usage('manual-history','inventory-a',
    '[{"product_id":"history-latte","quantity":4}]',current_date::timestamptz-interval '7 days',true,'Penjualan sebelum resep')$q$, 'USAGE_ID_CONFLICT');
  perform public.test_reject($q$select public.record_previous_sale_material_usage('unconfirmed','inventory-a',
    '[{"product_id":"history-latte","quantity":1}]',now(),false,null)$q$, 'PREVIOUS_SALE_CONFIRMATION_REQUIRED');
  perform public.test_reject($q$select public.record_previous_sale_material_usage('zero-history','inventory-a',
    '[{"product_id":"history-latte","quantity":0}]',now(),true,null)$q$, 'INVALID_USAGE_QUANTITY');
  perform public.test_reject($q$select public.record_previous_sale_material_usage('partial-history','inventory-a',
    '[{"product_id":"history-latte","quantity":1},{"product_id":"missing","quantity":1}]',now(),true,null)$q$, 'INVALID_USAGE_PRODUCT');
  perform public.test_assert((select quantity=before_beans-30 from public.ingredients where id='beans'), 'bad multi-item request rolls back every deduction');
end $$;
insert into public.products(id,outlet_id,name,price,cogs) values('no-recipe','inventory-a','Manual HPP','10000','5000');
select public.test_reject($q$select public.record_previous_sale_material_usage('unlinked','inventory-a',
  '[{"product_id":"no-recipe","quantity":1}]',now(),true,null)$q$, 'LINKED_RECIPE_REQUIRED');
select public.test_reject($q$select public.record_previous_sale_material_usage('future','inventory-a',
  '[{"product_id":"history-latte","quantity":1}]',now()+interval '1 day',true,null)$q$, 'INVALID_PREVIOUS_SALE_USAGE');
select public.test_reject($q$insert into public.expenses(id,outlet_id,category,description,amount,occurred_at)
  select 'internal:manual-history',outlet_id,'Wrong','Wrong',total_cogs::text,occurred_at
  from public.internal_material_usage where id='manual-history'$q$, 'INVALID_INTERNAL_USAGE_EXPENSE');
select public.test_reject($q$select public.record_previous_sale_material_usage('foreign-history','inventory-b',
  '[{"product_id":"history-latte","quantity":1}]',now(),true,null)$q$, 'OWNER_ACCESS_REQUIRED');
update public.expenses set amount='23000.0' where id='depletion:deplete-waste';
select public.test_reject($q$update public.expenses set amount='1' where id='depletion:deplete-waste'$q$, 'INGREDIENT_DEPLETION_EXPENSE_IMMUTABLE');
select public.test_reject($q$update public.expenses set outlet_id='inventory-b' where id='depletion:deplete-waste'$q$, 'INGREDIENT_DEPLETION_EXPENSE_IMMUTABLE');
select public.test_reject($q$delete from public.expenses where id='depletion:deplete-waste'$q$, 'INGREDIENT_DEPLETION_EXPENSE_IMMUTABLE');
select public.test_reject($q$insert into public.sync_tombstones(outlet_id,entity_type,record_id) values('inventory-a','expense','depletion:deplete-waste')$q$, 'INGREDIENT_DEPLETION_EXPENSE_IMMUTABLE');
select public.test_reject($q$insert into public.expenses(id,outlet_id,category,description,amount,occurred_at)
  select 'depletion:deplete-opening',outlet_id,'Bahan habis / selisih stok','Wrong',total_cost::text,occurred_at
  from public.ingredient_depletions where id='deplete-opening'$q$, 'INVALID_INGREDIENT_DEPLETION_EXPENSE');
select public.test_reject($q$select public.confirm_owner_ingredient_empty('deplete-foreign','inventory-b','deplete-milk','waste',now(),true,null)$q$, 'OWNER_ACCESS_REQUIRED');
select set_config('test.cloud','false',false);
select public.test_reject($q$select public.confirm_owner_ingredient_empty('deplete-free','inventory-a','deplete-milk','waste',now(),true,null)$q$, 'CLOUD_REQUIRED');
select public.test_reject($q$select public.record_previous_sale_material_usage('free-history','inventory-a',
  '[{"product_id":"history-latte","quantity":1}]',now(),true,null)$q$, 'CLOUD_REQUIRED');
select set_config('test.cloud','true',false);
select public.test_assert(not has_function_privilege('anon','public.confirm_owner_ingredient_empty(text,text,text,text,timestamptz,boolean,text)','execute'), 'anonymous depletion forbidden');
select public.test_assert(not has_function_privilege('anon','public.record_previous_sale_material_usage(text,text,jsonb,timestamptz,boolean,text)','execute'), 'anonymous previous sale forbidden');
select public.test_assert(not has_function_privilege('authenticated','public.guard_ingredient_depletion_expense()','execute'), 'expense guard is private');
select public.test_assert(not has_table_privilege('authenticated','public.ingredient_depletions','insert,update,delete'), 'receipts cannot be forged or changed');
set role authenticated;
select public.test_assert((select count(*)=3 from public.ingredient_depletions), 'owner can read receipts');
select set_config('test.outlet','inventory-b',false);
select public.test_assert((select count(*)=0 from public.ingredient_depletions), 'cross-outlet receipt isolation');
reset role;
select set_config('test.outlet','inventory-a',false);
