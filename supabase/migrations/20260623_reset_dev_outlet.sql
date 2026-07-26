-- DESTRUCTIVE: hapus seluruh outlet cloud dan semua data yang merujuk ke outlet.
-- Jalankan hanya pada project development.
begin;

truncate table outlets restart identity cascade;

insert into outlets (
  id,
  name,
  owner_email,
  address,
  phone,
  license_key,
  cloud_expiry,
  is_setup_done
)
values (
  'dev-aksal-outlet',
  'Sajia Dev Outlet',
  'aksalzilhamsyah0@gmail.com',
  'Development environment',
  null,
  'PRO',
  now() + interval '1 year',
  true
);

commit;
