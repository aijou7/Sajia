# Sajia 1.0.8

Rilis ini memusatkan perbaikan pada stabilitas transaksi, pemulihan akun,
keamanan lisensi, sinkronisasi lintas perangkat, dan pengalaman kasir F&B.

## Sorotan

- Login/daftar email memakai OTP 6 digit dengan normalisasi email, cooldown,
  timeout, pesan rate-limit, dan pemulihan PIN serta data bisnis pada perangkat
  baru.
- PIN kasir memiliki pembatasan percobaan dan tidak ada lagi akses demo pada
  build rilis.
- Navigasi utama dipadatkan menjadi maksimal lima tujuan tanpa animasi kedip;
  dashboard, laporan, pengaturan, dan shift berada di halaman `Lainnya`.
- Bottom sheet, form, tombol pembayaran, dan CTA aman dari keyboard serta
  navigation bar Android. Target sentuh kritis dinaikkan menjadi 48dp.
- Shift kasir mendukung modal awal, ringkasan tunai/QRIS, rekonsiliasi, dan
  penutupan dengan catatan serta selisih kas.
- Modifier produk mendukung grup wajib/opsional dan tambahan harga per opsi.
- Checkout, pengurangan stok, penyimpanan item, dan outbox sync berjalan dalam
  satu transaksi lokal; void mengembalikan stok secara idempotent.
- HPP dan kategori transaksi disimpan sebagai snapshot sehingga laporan lama
  tidak berubah saat produk diedit.
- Database lokal dienkripsi memakai SQLite3MultipleCiphers; backup tetap
  terenkripsi dan sisa file migrasi plaintext dibersihkan secara aman.
- Pembayaran Pro/Cloud memakai Midtrans dengan mode sandbox/production yang
  eksplisit, request checkout terbatas dan idempotent, serta webhook atomik dan
  tahan replay.
- Pro berlaku untuk akun owner, sedangkan Cloud tetap per outlet. Entitlement
  selalu divalidasi oleh server.
- Dashboard owner web kini responsif dan memiliki tampilan ringkasan,
  keuangan, serta cabang yang benar-benar dapat dinavigasi.

## Konfigurasi backend sebelum uji pembayaran

Jalankan migration dan deploy empat Edge Function sesuai
`supabase/README.md`. Untuk sandbox gunakan `SB-Mid-server-*` dan
`MIDTRANS_IS_PRODUCTION=false`. Saat akun Midtrans sudah aktif production,
ganti Server Key dan set `MIDTRANS_IS_PRODUCTION=true`, lalu deploy ulang
function pembayaran.

## Artefak Android

APK GitHub ditujukan untuk Android modern ARM64 dan merupakan build release
yang di-obfuscate. Artefak beta saat ini memakai sertifikat Android Debug agar
tetap kompatibel dengan instalasi uji sebelumnya. Untuk Google Play, buat AAB
dengan upload keystore permanen; build script kini menolak debug certificate
secara default agar artefak beta tidak salah diunggah ke production.

- File: `Sajia-v1.0.8-arm64.apk`
- Ukuran: 25.496.730 byte (24,32 MiB)
- SHA-256: `475ECB9C39D90FBE4CF10215CEA617BAA917E86205EAE718F5008DB48DC7398D`
