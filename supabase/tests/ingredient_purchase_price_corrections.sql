-- Disposable database only. Base inventory suite supplies test helpers.
insert into public.outlets(id,name,license_key) values('price-a','Prices','PRO-PRICE');
insert into public.users(id,name,pin,role,outlet_id) values('price-owner','Owner','123456','owner','price-a');
select set_config('test.outlet', 'price-a', false);
select public.save_owner_ingredient('price-milk','price-a','Susu','milliliter');
select public.record_ingredient_purchase('price-buy','price-a',
  '[{"ingredient_id":"price-milk","quantity":3,"unit":"liter","price":22000}]', current_date::timestamptz);
select public.save_owner_product_with_costing(
  '{"id":"price-coffee","outlet_id":"price-a","name":"Kopi Susu","price":"20000","base_cogs":"0","buffer_percent":0}',
  '[{"id":"price-recipe","ingredient_id":"price-milk","recipe_quantity":120,"recipe_unit":"milliliter"}]');
insert into public.orders(id,outlet_id,order_number,type,status,cashier_id,cashier_name,paid_at)
  values('price-sale','price-a','P1','takeaway','paid','price-owner','Owner',clock_timestamp());
insert into public.order_items(id,order_id,product_id,product_name,unit_price,quantity,subtotal,unit_cogs)
  values('price-sale-item','price-sale','price-coffee','Kopi Susu','20000','1','20000','880');
select public.record_ingredient_purchase('price-buy-later','price-a',
  '[{"ingredient_id":"price-milk","quantity":1,"unit":"liter","price":23000}]', current_date::timestamptz - interval '1 day');
create temporary table price_before as select * from public.ingredients where id='price-milk';
create temporary table price_movements_before as select * from public.ingredient_movements where outlet_id='price-a';
create temporary table price_receipts_before as select * from public.ingredient_purchases where outlet_id='price-a';
create temporary table price_recipes_before as select * from public.inventory_recipe_versions where outlet_id='price-a';
select public.correct_ingredient_purchase_prices('price-correction','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":66000}]',0,'3 liter × 22 ribu');
select public.test_assert((select quantity=3880 and abs(unit_cost-(2880*22.0+23000)/3880)<0.00000001
  from public.ingredients where id='price-milk'), 'weighted cost corrected in recording order, stock unchanged');
select public.test_assert((select total=66000 and previous_total=22000 and revision=1
  and corrected_by=auth.uid() from public.ingredient_purchase_price_corrections where id='price-correction'), 'audited price correction');
select public.test_assert(not exists((select * from public.ingredient_movements where outlet_id='price-a')
  except (select * from price_movements_before)), 'historical movements not repriced');
select public.test_assert(not exists((select * from public.ingredient_purchases where outlet_id='price-a')
  except (select * from price_receipts_before)), 'original purchase and retry fingerprints preserved');
select public.test_assert(not exists((select * from price_recipes_before)
  except (select * from public.inventory_recipe_versions where outlet_id='price-a')), 'old recipe versions retained');
select public.test_assert((select unit_cogs='880' from public.order_items where id='price-sale-item'), 'historical sale HPP frozen');
select public.test_assert((select cogs='2671' from public.products where id='price-coffee'), 'future recipe HPP updated');
select public.test_assert((select count(*)=1 from public.orders where outlet_id='price-a')
  and (select count(*)=0 from public.expenses where outlet_id='price-a'), 'correction creates no sale or expense');

-- Lost response and even old purchase retries do not create another receipt/stock.
select public.correct_ingredient_purchase_prices('price-correction','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":66000}]',0,'3 liter × 22 ribu');
select public.record_ingredient_purchase('price-buy','price-a',
  '[{"ingredient_id":"price-milk","quantity":3,"unit":"liter","price":22000}]', current_date::timestamptz);
select public.test_assert((select count(*)=1 from public.ingredient_purchase_price_corrections where outlet_id='price-a'), 'correction retry once');
select public.test_assert((select quantity=3880 from public.ingredients where id='price-milk'), 'purchase retry after correction preserves quantity');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('price-correction','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":60000}]',0,'3 liter × 22 ribu')$q$, 'PURCHASE_CORRECTION_ID_CONFLICT');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('stale','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":60000}]',0)$q$, 'PURCHASE_PRICE_CHANGED_RELOAD');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('same','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":66000}]',1)$q$, 'PURCHASE_PRICES_UNCHANGED');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('negative','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":-1}]',1)$q$, 'INVALID_PURCHASE_PRICE_CORRECTION');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('nan','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":"NaN"}]',1)$q$, 'INVALID_PURCHASE_PRICE_CORRECTION');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('tamper','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":60000,"quantity":9}]',1)$q$, 'INVALID_PURCHASE_PRICE_CORRECTION');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('foreign-item','price-a','price-buy',
  '[{"ingredient_id":"milk","price":60000}]',1)$q$, 'INVALID_PURCHASE_PRICE_CORRECTION');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('foreign','inventory-a','price-buy',
  '[{"ingredient_id":"price-milk","price":60000}]',1)$q$, 'OWNER_ACCESS_REQUIRED');
select set_config('test.cloud','false',false);
select public.test_reject($q$select public.correct_ingredient_purchase_prices('free','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":60000}]',1)$q$, 'CLOUD_REQUIRED');
select set_config('test.cloud','true',false);

-- Second revision and retry of an older request must not revert newer prices.
select public.correct_ingredient_purchase_prices('price-correction-2','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":69000}]',1);
select public.correct_ingredient_purchase_prices('price-correction','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":66000}]',0,'3 liter × 22 ribu');
select public.test_assert((select quantity=3880 and unit_cost=23 from public.ingredients where id='price-milk'), 'old correction retry cannot undo newer revision');

-- Fully consumed stock: a correction cannot contaminate a fresh later batch.
select public.apply_ingredient_movement('price-a','price-milk','internal','consume-old',-3880,23,clock_timestamp());
select public.record_ingredient_purchase('fresh','price-a',
  '[{"ingredient_id":"price-milk","quantity":1,"unit":"liter","price":25000}]',current_date::timestamptz);
select public.correct_ingredient_purchase_prices('price-correction-3','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":66000}]',2);
select public.test_assert((select quantity=1000 and unit_cost=25 from public.ingredients where id='price-milk'), 'fresh batch valuation resets after zero stock');

-- Any ledger inconsistency aborts the entire correction, including its audit.
update public.ingredients set quantity=999 where id='price-milk';
select public.test_reject($q$select public.correct_ingredient_purchase_prices('mismatch','price-a','price-buy',
  '[{"ingredient_id":"price-milk","price":63000}]',3)$q$, 'INGREDIENT_LEDGER_REVIEW_REQUIRED');
select public.test_assert(not exists(select 1 from public.ingredient_purchase_price_corrections where id='mismatch')
  and (select unit_cost=25 from public.ingredients where id='price-milk'), 'failed correction rolls back audit and valuation');
update public.ingredients set quantity=1000 where id='price-milk';

-- Multi-line price edits are all-or-nothing, including invalid/duplicate rows.
select public.save_owner_ingredient('price-syrup','price-a','Sirup','milliliter');
select public.record_ingredient_purchase('price-mixed','price-a',
  '[{"ingredient_id":"price-milk","quantity":1,"unit":"liter","price":25000},
    {"ingredient_id":"price-syrup","quantity":1,"unit":"liter","price":100000}]',current_date::timestamptz);
select public.test_reject($q$select public.correct_ingredient_purchase_prices('partial','price-a','price-mixed',
  '[{"ingredient_id":"price-milk","price":26000},{"ingredient_id":"price-syrup","price":-1}]',0)$q$, 'INVALID_PURCHASE_PRICE_CORRECTION');
select public.test_reject($q$select public.correct_ingredient_purchase_prices('duplicate','price-a','price-mixed',
  '[{"ingredient_id":"price-milk","price":26000},{"ingredient_id":"price-milk","price":120000}]',0)$q$, 'INVALID_PURCHASE_PRICE_CORRECTION');
select public.test_assert((select unit_cost=25 from public.ingredients where id='price-milk')
  and not exists(select 1 from public.ingredient_purchase_price_corrections where id in ('partial','duplicate')), 'invalid multi-line edit is atomic');
select public.correct_ingredient_purchase_prices('mixed-ok','price-a','price-mixed',
  '[{"ingredient_id":"price-milk","price":26000},{"ingredient_id":"price-syrup","price":120000}]',0);
select public.test_assert((select total=146000 from public.ingredient_purchase_price_corrections where id='mixed-ok')
  and (select quantity=2000 and unit_cost=25.5 from public.ingredients where id='price-milk')
  and (select quantity=1000 and unit_cost=120 from public.ingredients where id='price-syrup'), 'each line corrected using its own weighted cost');

-- Empty/negative stock and recorded operational expense retain their snapshots.
select public.confirm_owner_ingredient_empty('price-empty','price-a','price-syrup','personal',
  (select updated_at from public.ingredients where id='price-syrup'),true);
select public.correct_ingredient_purchase_prices('mixed-after-empty','price-a','price-mixed',
  '[{"ingredient_id":"price-milk","price":26000},{"ingredient_id":"price-syrup","price":125000}]',1);
select public.test_assert((select quantity=0 and unit_cost=125 from public.ingredients where id='price-syrup')
  and (select total_cost=120000 from public.ingredient_depletions where id='price-empty')
  and (select amount::numeric=120000 from public.expenses where id='depletion:price-empty'), 'old depletion expense is not rewritten at new prices');
select public.apply_ingredient_movement('price-a','price-syrup','internal','price-negative',-100,125,clock_timestamp());
select public.correct_ingredient_purchase_prices('mixed-negative','price-a','price-mixed',
  '[{"ingredient_id":"price-milk","price":26000},{"ingredient_id":"price-syrup","price":130000}]',2);
select public.test_assert((select quantity=-100 and unit_cost=130 from public.ingredients where id='price-syrup'), 'negative stock preserved, never clamped or fabricated');
select public.record_ingredient_purchase('price-negative-rebuy','price-a',
  '[{"ingredient_id":"price-syrup","quantity":1,"unit":"liter","price":140000}]',current_date::timestamptz);
select public.correct_ingredient_purchase_prices('mixed-negative-later','price-a','price-mixed',
  '[{"ingredient_id":"price-milk","price":26000},{"ingredient_id":"price-syrup","price":135000}]',3);
select public.test_assert((select quantity=900 and unit_cost=140 from public.ingredients where id='price-syrup'), 'purchase after negative balance resets current average');
select public.test_assert(not has_table_privilege('authenticated','public.ingredient_purchase_price_corrections','UPDATE')
  and not has_table_privilege('authenticated','public.ingredient_purchase_price_corrections','INSERT'), 'audit cannot be written directly');
select public.test_assert(not has_function_privilege('anon','public.correct_ingredient_purchase_prices(text,text,text,jsonb,bigint,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.revalue_ingredient_purchase_cost(text,text)','EXECUTE'), 'correction/helper grants restricted');
set role authenticated;
select public.test_assert((select count(*)=7 from public.ingredient_purchase_price_corrections), 'owner sees audit for own outlet');
select set_config('test.outlet','inventory-a',false);
select public.test_assert((select count(*)=0 from public.ingredient_purchase_price_corrections), 'RLS hides foreign outlet audit');
select set_config('test.outlet','price-a',false);
select set_config('test.cloud','false',false);
select public.test_assert((select count(*)=0 from public.ingredient_purchase_price_corrections), 'expired cloud cannot read audit');
reset role;
select set_config('test.cloud','true',false);
select set_config('test.outlet','inventory-a',false);
