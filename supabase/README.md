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
`MIDTRANS_IS_PRODUCTION=true`.

## 3. Deploy functions

```bash
supabase functions deploy create-plan-checkout --no-verify-jwt
supabase functions deploy get-plan-status --no-verify-jwt
supabase functions deploy midtrans-webhook --no-verify-jwt
```

## 4. Atur webhook

Midtrans Payment Notification URL:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/midtrans-webhook
```

## Alur pembayaran

1. App meminta checkout `PRO_LIFETIME` atau `CLOUD_MONTHLY` ke
   `create-plan-checkout`.
2. Function membuat checkout Midtrans dan menyimpan transaksi `PENDING`.
3. User membayar.
4. Webhook Midtrans memverifikasi signature dan nominal.
5. Webhook menandai transaksi `ACTIVE`, lalu update `license_key`/`cloud_expiry`.
6. App memanggil `get-plan-status` untuk refresh status lokal.

Pro adalah lisensi aplikasi sekali bayar. Cloud adalah add-on per outlet/bulan
untuk sync online dan dashboard owner lintas cabang.

Catatan legacy: beberapa kolom database masih bernama `xendit_*` untuk menjaga
kompatibilitas migration lama, tapi alur pembayaran aktif sekarang Midtrans-only.
