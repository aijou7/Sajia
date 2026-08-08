# Panduan Midtrans Production - Sajia

Dokumen ini digunakan setelah akun merchant Midtrans **sudah disetujui untuk Production**.

## Sebelum mengaktifkan Production

- Pastikan metode pembayaran Production yang diperlukan sudah aktif di dashboard Midtrans.
- Pastikan harga Sajia Pro dan Cloud sudah benar.
- Siapkan satu transaksi nyata untuk pengujian akhir.
- Jangan menyimpan Server Key di aplikasi, website, repository GitHub, screenshot, atau percakapan.

## 1. Ambil Production Server Key

1. Login ke Midtrans Dashboard.
2. Ubah environment di kiri atas dari **Sandbox** menjadi **Production**.
3. Buka **Settings > Access Keys**.
4. Salin **Production Server Key** ke password manager sementara.

Server Key Sandbox dan Production berbeda. Jangan menggunakan Client Key sebagai Server Key.

## 2. Ubah Supabase Edge Function Secrets

Buka **Supabase > Project pos_mobile > Edge Functions > Secrets**, lalu pastikan nilai berikut:

```text
PAYMENT_PROVIDER=MIDTRANS
MIDTRANS_SERVER_KEY=<PRODUCTION_SERVER_KEY>
MIDTRANS_IS_PRODUCTION=true
```

Harga tetap dikontrol oleh secret berikut:

```text
SAJIA_PRO_LIFETIME_PRICE=149000
SAJIA_CLOUD_MONTHLY_PRICE=10000
```

APK tidak perlu dibangun ulang. Fungsi `create-plan-checkout` akan menggunakan endpoint Production ketika `MIDTRANS_IS_PRODUCTION=true`.

## 3. Atur Notification URL Production

Di Midtrans Dashboard dalam environment **Production**, buka **Settings > Payment > Notification URL** dan masukkan:

```text
https://dglykanljjzysglwllju.supabase.co/functions/v1/midtrans-webhook
```

Simpan perubahan. Notification URL Sandbox dan Production dikonfigurasi secara terpisah.

Pada Supabase, konfigurasi **Verify JWT with legacy secret** untuk fungsi `midtrans-webhook` harus tetap **OFF**. Midtrans tidak mengirim JWT Supabase. Keaslian callback diverifikasi menggunakan signature SHA-512 dan Production Server Key.

## 4. Pengujian transaksi nyata

1. Buka aplikasi Sajia menggunakan akun owner.
2. Pilih upgrade Sajia Pro atau Cloud.
3. Pastikan halaman checkout tidak lagi bertanda **TEST**.
4. Bayar menggunakan metode Production yang aktif.
5. Pastikan transaksi Midtrans berstatus `settlement` atau `capture`.
6. Buka Supabase **Edge Functions > midtrans-webhook > Invocations**.
7. Pastikan callback terbaru menghasilkan HTTP `200`.
8. Pastikan paket aplikasi berubah menjadi `PRO` atau `CLOUD`.

## 5. Jika pembayaran berhasil tetapi paket belum aktif

- Periksa Notification History pada Midtrans.
- Periksa status invocation `midtrans-webhook` di Supabase.
- HTTP `401` biasanya berarti signature/key tidak cocok atau gateway JWT kembali aktif.
- HTTP `400` biasanya berarti payload atau jumlah pembayaran tidak cocok.
- HTTP `500` berarti pembaruan database gagal dan perlu diperiksa dari log fungsi.
- Jangan mengaktifkan paket secara manual sebelum status pembayaran dikonfirmasi dari Midtrans.

## Rollback ke Sandbox

Jika perlu menghentikan transaksi nyata selama investigasi:

```text
MIDTRANS_SERVER_KEY=<SANDBOX_SERVER_KEY>
MIDTRANS_IS_PRODUCTION=false
```

Pastikan kedua nilai berasal dari environment yang sama. Jangan memasangkan Production Server Key dengan endpoint Sandbox atau sebaliknya.

---

Sajia - dibuat oleh Aijou Teknologi Digital.
