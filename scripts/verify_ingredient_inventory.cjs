// Disposable PostgreSQL/WASM database; never connects to Supabase.
// Install @electric-sql/pglite outside the app and expose it via NODE_PATH.
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
(async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated;
      create schema auth;
      create function auth.uid() returns uuid language sql as $$ select '00000000-0000-0000-0000-000000000001'::uuid $$;
      grant usage on schema auth to authenticated, anon;`);
    const base = read('lib/supabase_schema.sql').split('-- SECURITY HARDENING')[0]
      .replace('create extension if not exists "uuid-ossp";', '');
    await db.exec(base);
    await db.exec(`create function public.current_user_has_outlet(p_id text) returns boolean language sql as $$ select p_id = current_setting('test.outlet', true) $$;
      create function public.current_user_has_cloud_outlet(p_id text) returns boolean language sql as $$ select public.current_user_has_outlet(p_id) and coalesce(current_setting('test.cloud', true), 'true') <> 'false' $$;
      select set_config('test.outlet', 'inventory-a', false);
      alter table public.order_items add column unit_cogs text;
      create table public.expenses(id text primary key, outlet_id text not null, category text not null, description text, amount text not null, occurred_at timestamptz not null);
      create table public.sync_tombstones(id uuid primary key default gen_random_uuid(), outlet_id text not null, entity_type text, record_id text, deleted_at timestamptz default now(), unique(entity_type,record_id));`);
    for (const file of [
      '20260925100000_product_cost_components.sql',
      '20260926100000_owner_managed_product_costing.sql',
      '20261007100000_owner_menu_deletion.sql',
      '20261007110000_ingredient_inventory.sql',
      '20261007130000_ingredient_depletion.sql',
    ]) await db.exec(read(`supabase/migrations/${file}`));
    await db.exec(read('supabase/tests/ingredient_inventory.sql'));
    await db.exec(read('supabase/tests/ingredient_depletion.sql'));
    const before = await db.query('select id,quantity,unit_cost from public.ingredients order by id');
    const receiptsBefore = await db.query('select id,total_cost,purpose from public.ingredient_depletions order by id');
    const expensesBefore = await db.query('select id,amount from public.expenses order by id');
    for (const file of ['20261007100000_owner_menu_deletion.sql', '20261007110000_ingredient_inventory.sql', '20261007130000_ingredient_depletion.sql']) {
      await db.exec(read(`supabase/migrations/${file}`));
    }
    const after = await db.query('select id,quantity,unit_cost from public.ingredients order by id');
    if (JSON.stringify(before.rows) !== JSON.stringify(after.rows)) throw new Error('Migration replay changed inventory');
    const receiptsAfter = await db.query('select id,total_cost,purpose from public.ingredient_depletions order by id');
    const expensesAfter = await db.query('select id,amount from public.expenses order by id');
    if (JSON.stringify(receiptsBefore.rows) !== JSON.stringify(receiptsAfter.rows) || JSON.stringify(expensesBefore.rows) !== JSON.stringify(expensesAfter.rows)) throw new Error('Migration replay changed financial receipts');
    console.log('PASS: purchases, recipes, sale/void, internal use, ingredient depletion, stale stock, duplicate retries, tenant access, expense protection and migration replay.');
  } finally { await db.close(); }
})().catch((error) => { console.error(error.message); process.exitCode = 1; });
