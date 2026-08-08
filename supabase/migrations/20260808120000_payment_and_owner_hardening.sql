-- Atomic Midtrans provisioning and normalized owner identity hardening.
-- Run after 20260808_sync_inventory_and_media_hardening.sql so this migration's
-- stricter replacement of the outlet insert trigger remains authoritative.

-- Owner e-mail is the tenant key used by the current Sajia Auth model. Store it
-- in one canonical form so every authorization decision can use exact equality
-- instead of wildcard/case-insensitive matching.
update outlets
set owner_email = nullif(lower(btrim(owner_email)), '')
where owner_email is distinct from nullif(lower(btrim(owner_email)), '');

create or replace function normalize_outlet_owner_email()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.owner_email := nullif(lower(btrim(new.owner_email)), '');
  return new;
end;
$$;

drop trigger if exists normalize_outlet_owner_email_before_write on outlets;
create trigger normalize_outlet_owner_email_before_write
before insert or update of owner_email on outlets
for each row execute function normalize_outlet_owner_email();

create index if not exists outlets_owner_email_exact_idx
  on outlets(owner_email)
  where owner_email is not null;

-- Direct PostgREST inserts remain available for first-device recovery, so the
-- database trigger must enforce the same exact owner identity and non-expired
-- Pro rule as create_owner_outlet_secure(). A modified client must not be able
-- to add branches with an expired PRO-prefixed license.
create or replace function enforce_owner_outlet_plan_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  request_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    auth.role()::text,
    ''
  );
  authenticated_email text := nullif(
    lower(btrim(coalesce(auth.jwt() ->> 'email', ''))),
    ''
  );
  normalized_email text := nullif(lower(btrim(new.owner_email)), '');
begin
  if request_role = 'authenticated' then
    if authenticated_email is null
        or normalized_email is distinct from authenticated_email then
      raise exception 'OWNER_EMAIL_MISMATCH' using errcode = '42501';
    end if;

    -- Serialize even direct PostgREST inserts. Without this lock, two first
    -- outlet requests could both observe an empty account and bypass Free's
    -- one-outlet limit before either transaction commits.
    perform pg_advisory_xact_lock(hashtext(authenticated_email)::bigint);

    if exists (
      select 1 from outlets outlet
      where outlet.owner_email = authenticated_email
    ) and not exists (
      select 1 from outlets outlet
      where outlet.owner_email = authenticated_email
        and upper(btrim(coalesce(outlet.license_key, ''))) like 'PRO%'
        and (outlet.license_expiry is null or outlet.license_expiry > now())
    ) then
      raise exception 'SAJIA_PRO_REQUIRED_FOR_ADDITIONAL_OUTLET'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function enforce_owner_outlet_plan_on_insert() from public;

-- Cloud sync is an outlet-scoped server entitlement. The helper deliberately
-- uses the normalized Auth e-mail with exact equality; organization membership
-- alone must not turn on paid operational sync.
create or replace function current_user_has_cloud_outlet(p_outlet_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and nullif(lower(btrim(coalesce(auth.jwt() ->> 'email', ''))), '') is not null
    and exists (
      select 1
      from outlets outlet
      where outlet.id = p_outlet_id
        and outlet.owner_email = nullif(
          lower(btrim(coalesce(auth.jwt() ->> 'email', ''))),
          ''
        )
        and upper(btrim(coalesce(outlet.license_key, ''))) like 'PRO%'
        and (outlet.license_expiry is null or outlet.license_expiry > now())
        and outlet.cloud_expiry > now()
    );
$$;

revoke all on function current_user_has_cloud_outlet(text)
  from public, anon;
grant execute on function current_user_has_cloud_outlet(text)
  to authenticated;

-- Stock sale/reversal is reconciled by immutable order id, never by an
-- absolute client stock snapshot. This keeps voids safe when two devices sell
-- the same product while one of them is offline.
create table if not exists applied_stock_sales (
  order_id text primary key references orders(id) on delete cascade,
  outlet_id text not null references outlets(id) on delete cascade,
  applied_at timestamptz not null default now()
);

alter table applied_stock_sales enable row level security;
revoke all on table applied_stock_sales from anon, authenticated;

create table if not exists reversed_stock_sales (
  order_id text primary key references orders(id) on delete cascade,
  outlet_id text not null references outlets(id) on delete cascade,
  reversed_at timestamptz not null default now()
);

alter table reversed_stock_sales enable row level security;
revoke all on table reversed_stock_sales from anon, authenticated;

create or replace function apply_order_stock_sale(p_order_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_outlet_id text;
  target_status text;
  sale_inserted integer;
  reversal_inserted integer;
begin
  select outlet_id, status
    into target_outlet_id, target_status
  from orders
  where id = p_order_id
  for update;

  if target_outlet_id is null
      or not current_user_has_cloud_outlet(target_outlet_id) then
    raise exception 'ORDER_ACCESS_REQUIRED';
  end if;
  if target_status not in ('paid', 'void') then
    raise exception 'ORDER_NOT_SETTLED';
  end if;
  if not exists (
    select 1 from order_items
    where order_id = p_order_id
      and coalesce(nullif(quantity, '')::numeric, 0) > 0
  ) then
    raise exception 'ORDER_ITEMS_NOT_READY';
  end if;

  insert into applied_stock_sales(order_id, outlet_id)
  values (p_order_id, target_outlet_id)
  on conflict (order_id) do nothing;
  get diagnostics sale_inserted = row_count;

  -- An offline paid order can already be void when first uploaded. Record the
  -- sale and its reversal together without changing stock: the correct net
  -- effect is zero.
  if target_status = 'void' then
    insert into reversed_stock_sales(order_id, outlet_id)
    values (p_order_id, target_outlet_id)
    on conflict (order_id) do nothing;
    get diagnostics reversal_inserted = row_count;

    -- If the sale was already applied on a previous sync, this invocation is
    -- also responsible for the additive reversal. This covers a client crash
    -- after the sale RPC succeeded but before its outbox row was marked done.
    if sale_inserted = 0 and reversal_inserted = 1 then
      with sold as (
        select product_id,
          sum(coalesce(nullif(quantity, '')::numeric, 0)) as quantity
        from order_items
        where order_id = p_order_id
        group by product_id
      )
      update products product
      set stock = (
            coalesce(nullif(product.stock, '')::numeric, 0) + sold.quantity
          )::text,
          updated_at = now()
      from sold
      where product.id = sold.product_id
        and product.outlet_id = target_outlet_id
        and product.track_stock = true;
    end if;
    return true;
  end if;

  if sale_inserted = 0 then
    return true;
  end if;

  with sold as (
    select product_id,
      sum(coalesce(nullif(quantity, '')::numeric, 0)) as quantity
    from order_items
    where order_id = p_order_id
    group by product_id
  )
  update products product
  set stock = greatest(
        0,
        coalesce(nullif(product.stock, '')::numeric, 0) - sold.quantity
      )::text,
      updated_at = now()
  from sold
  where product.id = sold.product_id
    and product.outlet_id = target_outlet_id
    and product.track_stock = true;

  return true;
end;
$$;

create or replace function reverse_order_stock_sale(p_order_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_outlet_id text;
  target_status text;
  sale_was_applied boolean;
  inserted_rows integer;
begin
  select outlet_id, status
    into target_outlet_id, target_status
  from orders
  where id = p_order_id
  for update;

  if target_outlet_id is null
      or not current_user_has_cloud_outlet(target_outlet_id) then
    raise exception 'ORDER_ACCESS_REQUIRED';
  end if;
  if target_status <> 'void' then
    raise exception 'ORDER_NOT_VOID';
  end if;

  select exists(
    select 1 from applied_stock_sales where order_id = p_order_id
  ) into sale_was_applied;

  -- When the paid sale never reached the server, consume both events as a
  -- no-op. A later retry therefore cannot create stock from nothing.
  if not sale_was_applied then
    insert into applied_stock_sales(order_id, outlet_id)
    values (p_order_id, target_outlet_id)
    on conflict (order_id) do nothing;
    insert into reversed_stock_sales(order_id, outlet_id)
    values (p_order_id, target_outlet_id)
    on conflict (order_id) do nothing;
    return true;
  end if;

  insert into reversed_stock_sales(order_id, outlet_id)
  values (p_order_id, target_outlet_id)
  on conflict (order_id) do nothing;
  get diagnostics inserted_rows = row_count;
  if inserted_rows = 0 then
    return true;
  end if;

  with sold as (
    select product_id,
      sum(coalesce(nullif(quantity, '')::numeric, 0)) as quantity
    from order_items
    where order_id = p_order_id
    group by product_id
  )
  update products product
  set stock = (
        coalesce(nullif(product.stock, '')::numeric, 0) + sold.quantity
      )::text,
      updated_at = now()
  from sold
  where product.id = sold.product_id
    and product.outlet_id = target_outlet_id
    and product.track_stock = true;

  return true;
end;
$$;

revoke all on function apply_order_stock_sale(text) from public, anon;
revoke all on function reverse_order_stock_sale(text) from public, anon;
grant execute on function apply_order_stock_sale(text) to authenticated;
grant execute on function reverse_order_stock_sale(text) to authenticated;

-- Free/Pro can recover identity, menu, staff and tables, but live operational
-- records only cross the network for the Cloud-enabled outlet.
drop policy if exists owner_scope_orders on orders;
create policy owner_scope_orders on orders
for all to authenticated
using (current_user_has_cloud_outlet(outlet_id))
with check (current_user_has_cloud_outlet(outlet_id));

drop policy if exists owner_scope_sessions on sessions;
create policy owner_scope_sessions on sessions
for all to authenticated
using (current_user_has_cloud_outlet(outlet_id))
with check (current_user_has_cloud_outlet(outlet_id));

drop policy if exists owner_scope_expenses on expenses;
create policy owner_scope_expenses on expenses
for all to authenticated
using (current_user_has_cloud_outlet(outlet_id))
with check (current_user_has_cloud_outlet(outlet_id));

drop policy if exists owner_scope_order_items on order_items;
create policy owner_scope_order_items on order_items
for all to authenticated
using (
  exists (
    select 1
    from orders order_row
    where order_row.id = order_items.order_id
      and current_user_has_cloud_outlet(order_row.outlet_id)
  )
)
with check (
  exists (
    select 1
    from orders order_row
    where order_row.id = order_items.order_id
      and current_user_has_cloud_outlet(order_row.outlet_id)
  )
);

alter table plan_orders
  add column if not exists checkout_fingerprint text,
  add column if not exists provider_environment text,
  add column if not exists failure_reason text;

create unique index if not exists plan_orders_checkout_fingerprint_idx
  on plan_orders(payment_provider, checkout_fingerprint)
  where checkout_fingerprint is not null;

-- The Edge Function authenticates the Midtrans signature. This function is
-- deliberately service-role-only and performs the order transition plus the
-- entitlement mutation in one database transaction. Replayed notifications
-- cannot add another Cloud month because ACTIVE orders are returned unchanged.
create or replace function process_midtrans_notification(
  p_order_id text,
  p_transaction_status text,
  p_fraud_status text,
  p_gross_amount numeric,
  p_paid_at timestamptz,
  p_reference_id text,
  p_environment text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    auth.role()::text,
    ''
  );
  payment_order plan_orders%rowtype;
  paid_outlet outlets%rowtype;
  normalized_status text := lower(btrim(coalesce(p_transaction_status, '')));
  normalized_fraud text := lower(btrim(coalesce(p_fraud_status, '')));
  normalized_environment text := lower(btrim(coalesce(p_environment, '')));
  effective_paid_at timestamptz := coalesce(p_paid_at, now());
  v_cloud_expiry timestamptz;
  is_paid boolean;
  next_status text;
begin
  if request_role <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if normalized_environment not in ('sandbox', 'production') then
    raise exception 'INVALID_PAYMENT_ENVIRONMENT' using errcode = '22023';
  end if;

  select payment.* into payment_order
  from plan_orders payment
  where payment.payment_provider = 'MIDTRANS'
    and payment.provider_order_id = p_order_id
  for update;

  if not found then
    -- Compatibility for an order created before provider_order_id was added.
    select payment.* into payment_order
    from plan_orders payment
    where payment.xendit_external_id = p_order_id
    for update;
  end if;

  if not found then
    return jsonb_build_object('found', false, 'outcome', 'ignored');
  end if;

  if coalesce(payment_order.provider_environment, normalized_environment)
      <> normalized_environment then
    raise exception 'PAYMENT_ENVIRONMENT_MISMATCH' using errcode = '22023';
  end if;

  is_paid := normalized_status = 'settlement'
    or (normalized_status = 'capture' and normalized_fraud = 'accept');

  if is_paid and p_gross_amount is distinct from payment_order.amount::numeric then
    raise exception 'PAYMENT_AMOUNT_MISMATCH' using errcode = '22023';
  end if;

  -- A valid duplicate notification is acknowledged without applying the plan
  -- a second time. ACTIVE is terminal for this provider order.
  if payment_order.status = 'ACTIVE' then
    return jsonb_build_object(
      'found', true,
      'outcome', 'already_active',
      'order_id', payment_order.id,
      'expires_at', payment_order.expires_at
    );
  end if;

  if is_paid then
    select outlet.* into paid_outlet
    from outlets outlet
    where outlet.id = payment_order.outlet_id
    for update;
    if not found then
      raise exception 'PAYMENT_OUTLET_NOT_FOUND' using errcode = 'P0002';
    end if;

    if payment_order.plan_code = 'PRO_LIFETIME' then
      if paid_outlet.owner_email is null then
        raise exception 'PAYMENT_OWNER_EMAIL_MISSING' using errcode = '22023';
      end if;

      update outlets
      set license_key = 'PRO',
          license_expiry = null
      where owner_email = paid_outlet.owner_email;
      v_cloud_expiry := null;
    elsif payment_order.plan_code = 'CLOUD_MONTHLY' then
      -- Cloud remains outlet-scoped even though Pro is owner-scoped.
      v_cloud_expiry := greatest(
        coalesce(paid_outlet.cloud_expiry, effective_paid_at),
        effective_paid_at
      ) + interval '1 month';

      update outlets
      set cloud_expiry = v_cloud_expiry
      where id = payment_order.outlet_id;
    else
      raise exception 'UNKNOWN_PLAN_CODE' using errcode = '22023';
    end if;

    update plan_orders
    set status = 'ACTIVE',
        paid_at = effective_paid_at,
        starts_at = effective_paid_at,
        expires_at = case
          when payment_order.plan_code = 'CLOUD_MONTHLY' then v_cloud_expiry
          else null
        end,
        provider_reference_id = coalesce(nullif(p_reference_id, ''), provider_reference_id),
        provider_environment = normalized_environment,
        failure_reason = null,
        updated_at = now()
    where id = payment_order.id;

    return jsonb_build_object(
      'found', true,
      'outcome', 'activated',
      'order_id', payment_order.id,
      'expires_at', v_cloud_expiry
    );
  end if;

  next_status := case normalized_status
    when 'expire' then 'EXPIRED'
    when 'cancel' then 'CANCELLED'
    when 'deny' then 'FAILED'
    when 'failure' then 'FAILED'
    when 'capture' then case
      when normalized_fraud = 'deny' then 'FAILED'
      else null
    end
    else null
  end;

  if next_status is not null then
    update plan_orders
    set status = next_status,
        provider_reference_id = coalesce(nullif(p_reference_id, ''), provider_reference_id),
        provider_environment = normalized_environment,
        failure_reason = case
          when normalized_status = 'capture' then 'MIDTRANS_CAPTURE_FRAUD_DENY'
          else 'MIDTRANS_' || upper(normalized_status)
        end,
        updated_at = now()
    where id = payment_order.id;
  elsif normalized_status in ('pending', 'capture') then
    -- A capture with fraud_status other than accept must not provision access.
    update plan_orders
    set provider_reference_id = coalesce(nullif(p_reference_id, ''), provider_reference_id),
        provider_environment = normalized_environment,
        updated_at = now()
    where id = payment_order.id;
  end if;

  return jsonb_build_object(
    'found', true,
    'outcome', coalesce(lower(next_status), 'pending'),
    'order_id', payment_order.id
  );
end;
$$;

revoke all on function process_midtrans_notification(
  text, text, text, numeric, timestamptz, text, text
) from public, anon, authenticated;
grant execute on function process_midtrans_notification(
  text, text, text, numeric, timestamptz, text, text
) to service_role;

-- Branch creation is serialized per owner so two simultaneous first-device
-- requests cannot bypass the one-outlet Free limit. Existing orphan rows are
-- never claimed implicitly.
create or replace function create_owner_outlet_secure(
  p_id text,
  p_name text,
  p_address text,
  p_phone text,
  p_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    auth.role()::text,
    ''
  );
  normalized_email text := nullif(lower(btrim(p_owner_email)), '');
  existing_outlet outlets%rowtype;
  created_outlet outlets%rowtype;
  owner_outlet_count bigint;
  owner_has_pro boolean;
begin
  if request_role <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if normalized_email is null then
    raise exception 'OWNER_EMAIL_REQUIRED' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext(normalized_email)::bigint);

  select count(*), coalesce(bool_or(
    upper(btrim(coalesce(outlet.license_key, ''))) like 'PRO%'
    and (outlet.license_expiry is null or outlet.license_expiry > now())
  ), false)
  into owner_outlet_count, owner_has_pro
  from outlets outlet
  where outlet.owner_email = normalized_email;

  select outlet.* into existing_outlet
  from outlets outlet
  where outlet.id = p_id
  for update;

  if found then
    if existing_outlet.owner_email is distinct from normalized_email then
      raise exception 'OUTLET_ID_ALREADY_EXISTS' using errcode = '23505';
    end if;
    return jsonb_build_object(
      'outlet', jsonb_build_object(
        'id', existing_outlet.id,
        'name', existing_outlet.name,
        'address', existing_outlet.address,
        'phone', existing_outlet.phone,
        'cloud_expiry', existing_outlet.cloud_expiry
      ),
      'is_pro', owner_has_pro,
      'is_cloud', owner_has_pro and existing_outlet.cloud_expiry > now(),
      'created', false
    );
  end if;

  if owner_outlet_count > 0 and not owner_has_pro then
    raise exception 'SAJIA_PRO_REQUIRED_FOR_ADDITIONAL_OUTLET' using errcode = '42501';
  end if;

  insert into outlets (
    id, name, address, phone, owner_email,
    license_key, license_expiry, cloud_expiry
  ) values (
    p_id,
    btrim(p_name),
    nullif(btrim(p_address), ''),
    nullif(btrim(p_phone), ''),
    normalized_email,
    case when owner_has_pro then 'PRO' else 'FREE' end,
    null,
    null
  ) returning * into created_outlet;

  return jsonb_build_object(
    'outlet', jsonb_build_object(
      'id', created_outlet.id,
      'name', created_outlet.name,
      'address', created_outlet.address,
      'phone', created_outlet.phone,
      'cloud_expiry', created_outlet.cloud_expiry
    ),
    'is_pro', owner_has_pro,
    'is_cloud', false,
    'created', true
  );
end;
$$;

revoke all on function create_owner_outlet_secure(text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function create_owner_outlet_secure(text, text, text, text, text)
  to service_role;

revoke all on function normalize_outlet_owner_email() from public;

-- Financial reports must use the values that were true when a sale happened.
-- Keeping these snapshots prevents later menu edits/deletes from rewriting
-- historical COGS and category reports.
alter table order_items
  add column if not exists unit_cogs text,
  add column if not exists category_id text,
  add column if not exists category_name text;

-- The owner dashboard is a Cloud feature. SECURITY DEFINER bypasses table RLS,
-- so the entitlement must be applied inside the function as well.
create or replace function get_owner_dashboard(
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  dashboard jsonb;
begin
  if current_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  perform ensure_owner_organization();

  if not exists (
    select 1
    from organization_members member
    where member.user_id = current_user_id
      and member.role in ('owner', 'admin')
  ) then
    raise exception 'OWNER_ACCESS_REQUIRED';
  end if;

  with accessible_outlets as (
    select distinct outlet.id, outlet.name
    from outlets outlet
    join outlet_organizations outlet_org on outlet_org.outlet_id = outlet.id
    join organization_members member
      on member.organization_id = outlet_org.organization_id
    where member.user_id = current_user_id
      and member.role in ('owner', 'admin')
      and current_user_has_cloud_outlet(outlet.id)
  ),
  paid_orders as (
    select order_row.id, order_row.outlet_id,
      coalesce(nullif(order_row.total, '')::numeric, 0) as total
    from orders order_row
    join accessible_outlets outlet on outlet.id = order_row.outlet_id
    where order_row.status = 'paid'
      and order_row.paid_at >= p_from
      and order_row.paid_at <= p_to
  ),
  revenue_by_outlet as (
    select outlet_id, coalesce(sum(total), 0) as revenue,
      count(*)::integer as transactions
    from paid_orders
    group by outlet_id
  ),
  cogs_by_outlet as (
    select paid.outlet_id,
      coalesce(sum(
        coalesce(
          nullif(item.unit_cogs, '')::numeric,
          nullif(product.cogs, '')::numeric,
          0
        ) * coalesce(nullif(item.quantity, '')::numeric, 0)
      ), 0) as cogs
    from paid_orders paid
    join order_items item on item.order_id = paid.id
    left join products product on product.id = item.product_id
    group by paid.outlet_id
  ),
  expenses_by_outlet as (
    select expense.outlet_id,
      coalesce(sum(coalesce(nullif(expense.amount, '')::numeric, 0)), 0)
        as expenses
    from expenses expense
    join accessible_outlets outlet on outlet.id = expense.outlet_id
    where expense.occurred_at >= p_from and expense.occurred_at <= p_to
    group by expense.outlet_id
  ),
  branches as (
    select outlet.id as outlet_id,
      outlet.name as outlet_name,
      coalesce(revenue.revenue, 0) as revenue,
      coalesce(cogs.cogs, 0) as cogs,
      coalesce(expense.expenses, 0) as expenses,
      coalesce(revenue.transactions, 0) as transactions
    from accessible_outlets outlet
    left join revenue_by_outlet revenue on revenue.outlet_id = outlet.id
    left join cogs_by_outlet cogs on cogs.outlet_id = outlet.id
    left join expenses_by_outlet expense on expense.outlet_id = outlet.id
  )
  select jsonb_build_object(
    'revenue', coalesce(sum(revenue), 0),
    'cogs', coalesce(sum(cogs), 0),
    'expenses', coalesce(sum(expenses), 0),
    'transactions', coalesce(sum(transactions), 0),
    'cloud_required', count(*) = 0,
    'branches', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'outlet_id', outlet_id,
          'outlet_name', outlet_name,
          'revenue', revenue,
          'cogs', cogs,
          'expenses', expenses,
          'transactions', transactions,
          'net_profit', revenue - cogs - expenses
        ) order by revenue desc
      ),
      '[]'::jsonb
    )
  ) into dashboard
  from branches;

  return dashboard;
end;
$$;

revoke all on function get_owner_dashboard(timestamptz, timestamptz)
  from public, anon;
grant execute on function get_owner_dashboard(timestamptz, timestamptz)
  to authenticated;
