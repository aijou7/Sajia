# Sajia Cloud, Multi Cabang, dan Midtrans Payments

Folder ini menampung migration Supabase dan Edge Functions untuk:

- pembayaran Pro/Cloud otomatis;
- owner dashboard web;
- sync multi-cabang;
- assignment manager/kasir ke cabang.

Secret payment hanya disimpan di Supabase, jangan pernah masuk APK Flutter,
GitHub, atau website statis.

## 1. Jalankan migration

Di Supabase SQL Editor, jalankan berurutan:

```text
supabase/migrations/20260622_xendit_pro.sql
supabase/migrations/20260623_owner_portal.sql
supabase/migrations/20260623_owner_device_recovery.sql
supabase/migrations/20260630_multi_branch_access_sync_payment.sql
supabase/migrations/20260707_server_owned_entitlements.sql
supabase/migrations/20260808_sync_inventory_and_media_hardening.sql
supabase/migrations/20260808120000_payment_and_owner_hardening.sql
supabase/migrations/20260808130000_sync_relationship_tombstones.sql
```

## 2. Set secrets Midtrans

Rekomendasi untuk akun individu: pakai Midtrans Snap.

```bash
supabase secrets set \
  PAYMENT_PROVIDER=MIDTRANS \
  MIDTRANS_SERVER_KEY=SB-Mid-server-xxxxxxxx \
  MIDTRANS_IS_PRODUCTION=false \
  SAJIA_PRO_LIFETIME_PRICE=149000 \
  SAJIA_CLOUD_MONTHLY_PRICE=10000 \
  SAJIA_PAYMENT_SUCCESS_URL=https://sajia-owner.pages.dev/payment/success \
  SAJIA_PAYMENT_FAILURE_URL=https://sajia-owner.pages.dev/payment/failed
```

Saat production, ganti `MIDTRANS_SERVER_KEY` ke production key dan set
`MIDTRANS_IS_PRODUCTION=true`. Function sengaja fail-closed: mode sandbox hanya
menerima key `SB-Mid-server-*`, sedangkan production hanya menerima
`Mid-server-*`. `PAYMENT_PROVIDER` juga wajib bernilai `MIDTRANS`.

Untuk mengaktifkan verifikasi APK resmi pada checkout production, build Android
dengan Cloud project number dan set secret Play Integrity secara berpasangan:

```bash
flutter build appbundle --release \
  --dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=YOUR_GOOGLE_CLOUD_PROJECT_NUMBER \
  --dart-define=ENABLE_CLOUD_SYNC=true

supabase secrets set \
  PLAY_INTEGRITY_ENFORCE_PAYMENT=true \
  PLAY_INTEGRITY_PACKAGE_NAME=id.aksaldev.sajia \
  PLAY_INTEGRITY_CERT_SHA256=YOUR_PLAY_CERTIFICATE_SHA256_DIGEST \
  GOOGLE_SERVICE_ACCOUNT_JSON='YOUR_SERVICE_ACCOUNT_JSON'
```

`PLAY_INTEGRITY_ENFORCE_PAYMENT=true` tanpa Dart define atau credential Google
yang benar akan menolak seluruh checkout secara fail-closed. Untuk APK sandbox
yang belum didistribusikan melalui Google Play, biarkan flag tersebut `false`.

## 3. Deploy functions

```bash
supabase functions deploy midtrans-webhook --no-verify-jwt
supabase functions deploy get-plan-status --no-verify-jwt
supabase functions deploy create-owner-outlet --no-verify-jwt
supabase functions deploy create-plan-checkout --no-verify-jwt
```

Deploy webhook lebih dulu dan checkout terakhir supaya tidak ada jendela waktu
di mana pembayaran dapat dibuat tetapi callback belum tersedia.

Keempat function di atas tetap memverifikasi sesi/signature sendiri. Jangan
deploy ulang function legacy `create-pro-checkout`, `get-pro-status`, atau
`xendit-webhook`; hapus deployment lama dan callback Xendit sebelum production.

## 4. Atur webhook

Midtrans Payment Notification URL:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/midtrans-webhook
```

## 5. Verifikasi konfigurasi OTP sebelum rilis

- Authentication > Sign In / Providers: Email aktif dan pendaftaran user baru
  diizinkan.
- Template **Magic link or OTP** menampilkan `{{ .Token }}` (6 digit), bukan
  hanya `{{ .ConfirmationURL }}`.
- Custom SMTP aktif dengan sender/domain yang sudah terverifikasi; lakukan tes
  kirim dari Supabase setelah mengubah credential SMTP.
- Interval kirim per user minimal 60 detik agar sama dengan cooldown aplikasi.
- Smoke-test dua alur terpisah: daftar dengan email baru, lalu masuk/ganti
  perangkat dengan email owner yang sudah ada.

## Alur pembayaran

1. App meminta checkout `PRO_LIFETIME` atau `CLOUD_MONTHLY` ke
   `create-plan-checkout`.
2. Function membuat checkout Midtrans dan menyimpan transaksi `PENDING`.
3. User membayar.
4. Webhook Midtrans memverifikasi signature dan nominal.
5. Webhook menjalankan RPC transaksional yang sekaligus menandai transaksi
   `ACTIVE` dan memperbarui `license_key`/`cloud_expiry` secara idempotent.
6. App memanggil `get-plan-status` untuk refresh status lokal.

Pro adalah lisensi aplikasi sekali bayar. Cloud adalah add-on per outlet/bulan
untuk sync online dan dashboard owner lintas cabang.

Checkout `PENDING` disimpan sebelum Snap dipanggil, dibatasi per outlet, dan
request berulang memakai checkout aktif yang sama. Cloud hanya diperpanjang
untuk outlet yang dibayar; replay webhook tidak menambah bulan kedua kali.
RLS juga membatasi sinkronisasi order, item order, sesi, dan pengeluaran hanya
ke outlet dengan Cloud aktif. Data pemulihan akun, menu, staff, dan meja tetap
tersedia sesuai paket aplikasi.

Catatan legacy: beberapa kolom database masih bernama `xendit_*` untuk menjaga
kompatibilitas migration lama, tapi alur pembayaran aktif sekarang Midtrans-only.
