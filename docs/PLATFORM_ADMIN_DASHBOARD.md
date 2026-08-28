# Dashboard admin paket Sajia

Dashboard owner di `/sajia/owner` punya mode **Akun & paket** untuk admin
platform. Mode ini dapat melihat seluruh akun owner, mengubah paket menjadi
Free, Pro, atau Cloud, dan menyimpan perubahan beserta alasan ke audit log.

## Aktivasi admin pertama

Migration `20260828120000_platform_entitlement_admin.sql` sengaja tidak
memberi akses admin ke user mana pun secara otomatis. Pilih salah satu cara
berikut di Supabase Dashboard untuk akun internal Aijou:

1. Buka Authentication → Users → user internal.
2. Edit **User Metadata / App metadata** menjadi atau gabungkan dengan:

   ```json
   {"role":"platform_admin"}
   ```

3. Keluar lalu masuk kembali ke dashboard supaya JWT mengambil metadata baru.

Alternatif yang lebih mudah dicabut adalah memasukkan UUID user internal ke
tabel `platform_admins` melalui SQL Editor:

```sql
insert into public.platform_admins (user_id, email)
select id, email
from auth.users
where lower(email) = lower('EMAIL_INTERNAL_AIJOU');
```

Jangan masukkan service-role key ke APK, browser, atau repository. Tabel
entitlement dan audit log tidak punya akses langsung untuk `anon` maupun
`authenticated`; semua perubahan harus melewati RPC yang memeriksa admin.

## Arti paket

- **Free**: semua outlet owner memakai `FREE`, tanpa Cloud.
- **Pro**: semua outlet owner memakai `PRO`, tanpa Cloud.
- **Cloud**: semua outlet owner memakai `PRO` dan Cloud aktif sampai tanggal
  yang dipilih.

Perubahan akun dikunci dalam satu transaksi dan dicatat dengan state sebelum,
state sesudah, actor, waktu, serta alasan. Cloud hanya dapat disimpan dengan
tanggal kedaluwarsa di masa depan.
