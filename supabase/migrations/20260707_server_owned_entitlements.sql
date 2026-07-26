-- Sajia anti-crack hardening.
--
-- Plan entitlements must be server-owned. Mobile/web clients may edit outlet
-- profile fields, but they must never be able to promote an outlet to Pro or
-- Cloud by sending license_key/license_expiry/cloud_expiry directly.
--
-- Run this in Supabase SQL Editor after the 20260630 migration.

alter table outlets alter column license_key set default 'FREE';

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
begin
  if request_role in ('anon', 'authenticated') then
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

drop trigger if exists protect_outlet_entitlements_before_write on outlets;
create trigger protect_outlet_entitlements_before_write
before insert or update on outlets
for each row execute function protect_outlet_entitlement_fields();

revoke all on function protect_outlet_entitlement_fields() from public;
