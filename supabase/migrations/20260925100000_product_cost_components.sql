-- Per-menu recipe lines used to calculate HPP from the actual package price.
-- The mobile client keeps the calculator offline-first and syncs these rows
-- independently from products, so existing clients remain compatible.
create table if not exists product_cost_components (
  id text primary key,
  outlet_id text not null,
  product_id text not null,
  material_name text not null,
  package_quantity numeric not null,
  package_unit text not null,
  package_price numeric not null default 0,
  recipe_quantity numeric not null,
  recipe_unit text not null,
  updated_at timestamptz not null default now()
);

create index if not exists idx_product_cost_components_product
  on product_cost_components(product_id);
create index if not exists idx_product_cost_components_outlet_updated
  on product_cost_components(outlet_id, updated_at desc);

alter table product_cost_components enable row level security;

revoke all on table product_cost_components from anon;
grant select, insert, update, delete on table product_cost_components to authenticated;

drop policy if exists owner_scope_product_cost_components
  on product_cost_components;
create policy owner_scope_product_cost_components
  on product_cost_components
  for all to authenticated
  using (current_user_has_outlet(outlet_id))
  with check (current_user_has_outlet(outlet_id));
