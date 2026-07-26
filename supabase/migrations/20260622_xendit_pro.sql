-- Sajia Pro payments via Xendit. Run this in the Supabase SQL Editor.

alter table outlets add column if not exists cloud_expiry timestamptz;

create table if not exists plan_orders (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references outlets(id) on delete cascade,
  plan_code text not null check (plan_code in ('PRO_LIFETIME', 'CLOUD_MONTHLY')),
  status text not null check (status in ('PENDING', 'ACTIVE', 'EXPIRED', 'FAILED', 'CANCELLED')),
  amount bigint not null check (amount > 0),
  currency text not null default 'IDR',
  xendit_invoice_id text unique,
  xendit_external_id text unique not null,
  checkout_url text,
  paid_at timestamptz,
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists plan_orders_outlet_created_idx
  on plan_orders(outlet_id, created_at desc);

alter table plan_orders enable row level security;
revoke all on table plan_orders from anon, authenticated;
