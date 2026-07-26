-- Owner device recovery via verified Supabase Auth email.
-- The browser/mobile client never receives another owner's outlet.
create or replace function get_authenticated_owner_outlets()
returns table (
  id text,
  name text,
  address text,
  phone text,
  license_key text,
  cloud_expiry timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    outlet.id,
    outlet.name,
    outlet.address,
    outlet.phone,
    outlet.license_key,
    outlet.cloud_expiry
  from outlets outlet
  where auth.uid() is not null
    and lower(coalesce(outlet.owner_email, '')) =
        lower(coalesce(auth.jwt() ->> 'email', ''))
  order by outlet.created_at asc;
$$;

revoke all on function get_authenticated_owner_outlets() from public;
grant execute on function get_authenticated_owner_outlets() to authenticated;
