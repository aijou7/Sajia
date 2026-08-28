# Dashboard admin paket Sajia

Dashboard owner di `/sajia/owner` punya mode **Akun & paket** untuk admin
platform. Mode ini dapat melihat seluruh akun owner, mengubah paket menjadi
Free, Pro, atau Cloud, dan menyimpan perubahan beserta alasan ke audit log.

## Login dashboard

Login aplikasi kasir tetap menggunakan email + OTP. Dashboard owner mempunyai
password terpisah agar login harian tidak perlu meminta OTP terus-menerus.

- Pertama kali, pilih **Belum punya password? Buat/reset via OTP**, masukkan
  email owner yang sudah terdaftar di aplikasi, lalu buat password minimal 8
  karakter dengan setidaknya 1 angka.
- Setelah OTP berhasil diverifikasi, password disimpan di Supabase Auth dan
  login dashboard berikutnya cukup memakai email + password.
- Link yang sama dapat dipakai untuk mengganti password. Password dashboard
  tidak mengubah atau menggantikan mekanisme OTP di aplikasi kasir.

Akun internal dev/admin mengikuti flow yang sama. Gunakan email Auth internal
yang terpisah dari akun owner pelanggan, lalu berikan `app_metadata.role`
`platform_admin` seperti di bawah agar setelah login password mode admin
terbuka.

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
