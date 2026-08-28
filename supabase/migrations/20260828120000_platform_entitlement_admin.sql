-- Platform entitlement administration for Sajia support.
--
-- Customer owner accounts remain scoped by owner_email. Only an explicitly
-- designated platform admin may list all accounts or change Pro/Cloud access.
-- Entitlements are still server-owned: browser clients can call the guarded
-- RPCs, but they cannot update outlet plan columns directly.

create table if not exists platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists platform_admins_email_idx
  on platform_admins (lower(email));

alter table platform_admins enable row level security;
revoke all on table platform_admins from anon, authenticated;

create table if not exists platform_entitlement_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_email text,
  owner_email text not null,
  previous_state jsonb not null,
  next_state jsonb not null,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists platform_entitlement_audit_owner_idx
  on platform_entitlement_audit_log (owner_email, created_at desc);

alter table platform_entitlement_audit_log enable row level security;
revoke all on table platform_entitlement_audit_log from anon, authenticated;

create or replace function is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and (
      lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) in
        ('platform_admin', 'super_admin')
      or exists (
        select 1
        from platform_admins admin
        where admin.user_id = auth.uid()
          and admin.is_active = true
      )
    );
$$;

revoke all on function is_platform_admin() from public, anon;
grant execute on function is_platform_admin() to authenticated;

create or replace function get_platform_admin_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('is_admin', is_platform_admin());
$$;

revoke all on function get_platform_admin_context() from public, anon;
grant execute on function get_platform_admin_context() to authenticated;

create or replace function get_platform_entitlement_accounts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  accounts jsonb;
begin
  if not is_platform_admin() then
    raise exception 'PLATFORM_ADMIN_REQUIRED' using errcode = '42501';
  end if;

  with grouped_accounts as (
    select
      lower(btrim(outlet.owner_email)) as owner_email,
      count(*)::integer as outlet_count,
      count(*) filter (
        where upper(btrim(coalesce(outlet.license_key, ''))) like 'PRO%'
          and (outlet.license_expiry is null or outlet.license_expiry > now())
      )::integer as pro_outlet_count,
      count(*) filter (
        where upper(btrim(coalesce(outlet.license_key, ''))) like 'PRO%'
          and (outlet.license_expiry is null or outlet.license_expiry > now())
          and outlet.cloud_expiry > now()
      )::integer as cloud_outlet_count,
      min(outlet.cloud_expiry) filter (
        where upper(btrim(coalesce(outlet.license_key, ''))) like 'PRO%'
          and (outlet.license_expiry is null or outlet.license_expiry > now())
          and outlet.cloud_expiry > now()
      ) as cloud_expiry,
      jsonb_agg(
        jsonb_build_object(
          'id', outlet.id,
          'name', outlet.name,
          'license_key', outlet.license_key,
          'license_expiry', outlet.license_expiry,
          'cloud_expiry', outlet.cloud_expiry
        ) order by outlet.created_at asc, outlet.id
      ) as outlets
    from outlets outlet
    where nullif(lower(btrim(outlet.owner_email)), '') is not null
    group by lower(btrim(outlet.owner_email))
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'owner_email', account.owner_email,
        'outlet_count', account.outlet_count,
        'pro_outlet_count', account.pro_outlet_count,
        'cloud_outlet_count', account.cloud_outlet_count,
        'plan_code', case
          when account.pro_outlet_count = 0 then 'FREE'
          when account.pro_outlet_count = account.outlet_count
            and account.cloud_outlet_count = account.outlet_count then 'CLOUD'
          when account.pro_outlet_count = account.outlet_count then 'PRO'
          else 'MIXED'
        end,
        'cloud_expiry', account.cloud_expiry,
        'outlets', account.outlets,
        'last_changed_at', (
          select max(audit.created_at)
          from platform_entitlement_audit_log audit
          where audit.owner_email = account.owner_email
        )
      ) order by account.owner_email
    ),
    '[]'::jsonb
  )
  into accounts
  from grouped_accounts account;

  return accounts;
end;
$$;

revoke all on function get_platform_entitlement_accounts() from public, anon;
grant execute on function get_platform_entitlement_accounts() to authenticated;

-- The entitlement trigger already blocks authenticated direct writes. This
-- trusted transaction-local marker gives only the guarded admin RPC a narrow
-- path to change the server-owned fields without exposing table write access.
create or replace function protect_outlet_entitlement_fields()
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
  trusted_context boolean := current_setting(
    'sajia.entitlement_write_context',
    true
  ) = 'platform_admin';
begin
  if request_role in ('anon', 'authenticated') and not trusted_context then
    if tg_op = 'INSERT' then
      new.license_key := 'FREE';
      new.license_expiry := null;
      new.cloud_expiry := null;
    elsif tg_op = 'UPDATE' then
      if new.license_key is distinct from old.license_key
        or new.license_expiry is distinct from old.license_expiry
        or new.cloud_expiry is distinct from old.cloud_expiry then
        raise exception 'PLAN_ENTITLEMENT_IS_SERVER_OWNED'
          using errcode = '42501';
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function protect_outlet_entitlement_fields() from public;

create or replace function set_platform_entitlement(
  p_owner_email text,
  p_plan_code text,
  p_cloud_expiry timestamptz default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text := nullif(lower(btrim(coalesce(p_owner_email, ''))), '');
  normalized_plan text := upper(btrim(coalesce(p_plan_code, '')));
  actor_email text := nullif(lower(btrim(coalesce(auth.jwt() ->> 'email', ''))), '');
  previous_state jsonb;
  next_state jsonb;
  changed_at timestamptz := now();
begin
  if not is_platform_admin() then
    raise exception 'PLATFORM_ADMIN_REQUIRED' using errcode = '42501';
  end if;
  if normalized_email is null or length(normalized_email) > 320 then
    raise exception 'OWNER_EMAIL_REQUIRED' using errcode = '22023';
  end if;
  if normalized_plan not in ('FREE', 'PRO', 'CLOUD') then
    raise exception 'INVALID_ENTITLEMENT_PLAN' using errcode = '22023';
  end if;
  if normalized_plan = 'CLOUD'
      and (p_cloud_expiry is null or p_cloud_expiry <= now()) then
    raise exception 'CLOUD_EXPIRY_REQUIRED' using errcode = '22023';
  end if;

  if not exists (
    select 1 from outlets outlet where outlet.owner_email = normalized_email
  ) then
    raise exception 'OWNER_ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Serialize account-wide changes so a support operator never records a
  -- partial state while another entitlement change is in flight.
  perform 1
  from outlets outlet
  where outlet.owner_email = normalized_email
  for update;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', outlet.id,
        'license_key', outlet.license_key,
        'license_expiry', outlet.license_expiry,
        'cloud_expiry', outlet.cloud_expiry
      ) order by outlet.id
    ),
    '[]'::jsonb
  )
  into previous_state
  from outlets outlet
  where outlet.owner_email = normalized_email;

  perform set_config(
    'sajia.entitlement_write_context',
    'platform_admin',
    true
  );

  if normalized_plan = 'FREE' then
    update outlets
    set license_key = 'FREE',
        license_expiry = null,
        cloud_expiry = null
    where owner_email = normalized_email;
  elsif normalized_plan = 'PRO' then
    update outlets
    set license_key = 'PRO',
        license_expiry = null,
        cloud_expiry = null
    where owner_email = normalized_email;
  else
    update outlets
    set license_key = 'PRO',
        license_expiry = null,
        cloud_expiry = p_cloud_expiry
    where owner_email = normalized_email;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', outlet.id,
        'license_key', outlet.license_key,
        'license_expiry', outlet.license_expiry,
        'cloud_expiry', outlet.cloud_expiry
      ) order by outlet.id
    ),
    '[]'::jsonb
  )
  into next_state
  from outlets outlet
  where outlet.owner_email = normalized_email;

  insert into platform_entitlement_audit_log (
    actor_user_id,
    actor_email,
    owner_email,
    previous_state,
    next_state,
    reason,
    created_at
  ) values (
    auth.uid(),
    actor_email,
    normalized_email,
    previous_state,
    next_state,
    nullif(left(btrim(coalesce(p_reason, '')), 500), ''),
    changed_at
  );

  return jsonb_build_object(
    'owner_email', normalized_email,
    'plan_code', normalized_plan,
    'cloud_expiry', case
      when normalized_plan = 'CLOUD' then p_cloud_expiry
      else null
    end,
    'outlet_count', jsonb_array_length(next_state),
    'changed_at', changed_at
  );
end;
$$;

revoke all on function set_platform_entitlement(text, text, timestamptz, text)
  from public, anon;
grant execute on function set_platform_entitlement(text, text, timestamptz, text)
  to authenticated;

create or replace function get_platform_entitlement_audit(p_limit integer default 50)
returns table (
  id uuid,
  actor_email text,
  owner_email text,
  previous_state jsonb,
  next_state jsonb,
  reason text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    audit.id,
    audit.actor_email,
    audit.owner_email,
    audit.previous_state,
    audit.next_state,
    audit.reason,
    audit.created_at
  from platform_entitlement_audit_log audit
  where is_platform_admin()
  order by audit.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

revoke all on function get_platform_entitlement_audit(integer) from public, anon;
grant execute on function get_platform_entitlement_audit(integer) to authenticated;
