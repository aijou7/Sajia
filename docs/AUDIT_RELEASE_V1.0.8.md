# Audit Rilis Sajia 1.0.8

Tanggal audit: 8 Agustus 2026

Dokumen ini mencatat cakupan verifikasi rilis. Audit menutup blocker yang
ditemukan melalui pemeriksaan kode, analisis statis, pengujian otomatis, dan
pengujian konfigurasi backend. Audit perangkat nyata tetap perlu dilakukan
pada APK final sebelum promosi ke production.

## Hasil utama

- Akses demo/bypass PIN dihapus dari build publik.
- Login dan pendaftaran memakai OTP email enam digit, normalisasi email,
  cooldown 60 detik, timeout, serta pesan kesalahan yang dapat ditindaklanjuti.
- Owner yang masuk di perangkat baru memulihkan PIN, cabang, menu, produk,
  staff, meja, dan data Cloud tanpa membuat identitas owner baru.
- Percobaan PIN dibatasi; PIN staff yang sama dalam satu outlet ditolak.
- Hak akses antarmuka dibedakan untuk owner, manager, dan kasir.
- Transaksi, item, stok, dan outbox disimpan atomik. Void bersifat idempotent
  dan mengembalikan stok lokal.
- HPP dan kategori disimpan sebagai snapshot transaksi agar laporan historis
  tidak berubah saat menu diedit.
- Database perangkat dan backup lokal dienkripsi.
- Sinkronisasi mengirim tombstone untuk penghapusan meja dan assignment staff
  agar data yang sudah dihapus tidak muncul kembali.
- Midtrans memakai mode eksplisit, checkout idempotent/terbatas, serta webhook
  yang memverifikasi signature, nominal, environment, dan replay secara atomik.
- Pro divalidasi untuk akun owner; Cloud divalidasi per outlet oleh server.
- Navigasi, bottom sheet, CTA, keyboard, dan system navigation bar telah
  diperbaiki untuk layar Android modern. Empty/loading/error state dibuat
  konsisten dan target sentuh penting minimal 48 dp.
- Shift kasir dan rekonsiliasi kas tersedia. Modifier produk mendukung grup
  wajib/opsional dan tambahan harga.

## Verifikasi otomatis

- `flutter analyze --no-pub`
- seluruh `flutter test --no-pub`
- focused test OTP, payment safety, transaction integrity, snapshot laporan,
  database migration cleanup, modifier, dan sync tombstone
- release build Android ARM64 dengan obfuscation; signature beta diverifikasi
- release build dashboard owner web

Hasil perintah final dan checksum artefak dicatat pada GitHub Release V1.0.8.

## Backend yang harus dipertahankan

Migration dijalankan sesuai urutan di `supabase/README.md`, tanpa menjalankan
`20260623_reset_dev_outlet.sql`. Edge Function aktif hanya alur Midtrans:

- `create-plan-checkout`
- `get-plan-status`
- `create-owner-outlet`
- `midtrans-webhook`

Function/callback Xendit lama tidak boleh dideploy lagi.

## Checklist OTP production

- Email provider dan pendaftaran user aktif.
- Confirm email aktif.
- Template **Magic link or OTP** menggunakan `{{ .Token }}`.
- Custom SMTP aktif dengan sender dan domain terverifikasi.
- Minimum interval SMTP dan cooldown aplikasi sama-sama 60 detik atau lebih.
- Sebelum promosi, lakukan satu tes daftar email baru dan satu tes login owner
  lama pada perangkat kedua sampai kode benar-benar diterima di inbox.

## Pindah Midtrans sandbox ke production

1. Ganti secret `MIDTRANS_SERVER_KEY` dengan Server Key production
   (`Mid-server-*`, bukan `SB-Mid-server-*`).
2. Set `MIDTRANS_IS_PRODUCTION=true` dan pastikan
   `PAYMENT_PROVIDER=MIDTRANS`.
3. Pertahankan Payment Notification URL ke
   `https://dglykanljjzysglwllju.supabase.co/functions/v1/midtrans-webhook`.
4. Lakukan transaksi nominal kecil dan pastikan status berubah dari `PENDING`
   menjadi `ACTIVE` tepat satu kali.

Function sengaja menolak konfigurasi mode/key yang tidak cocok. Karena itu,
respons `Service unavailable` sebelum secret production benar adalah perilaku
fail-closed, bukan alasan untuk menaruh Server Key di aplikasi.

## Risiko residual yang terdokumentasi

Role staff saat ini memakai sesi Supabase owner yang dipertahankan di perangkat,
sedangkan pembatasan owner/manager/kasir diterapkan oleh aplikasi. Ini aman
untuk penggunaan operasional pada APK resmi, tetapi APK yang dimodifikasi pada
perangkat staff yang tidak dipercaya dapat mencoba memakai token owner. Untuk
isolasi hostile-staff tingkat tinggi, versi lanjutan perlu memberi setiap staff
akun Supabase Auth/claim sendiri dan menegakkan role serta outlet di RLS.

Play Integrity sudah disiapkan untuk checkout production. Enforcement jangan
diaktifkan pada APK GitHub/sideload karena verdict Play-recognized umumnya baru
valid setelah distribusi melalui Google Play.

APK GitHub V1.0.8 masih memakai Android Debug certificate untuk kompatibilitas
dengan instalasi beta sebelumnya. Ia bukan artefak Google Play. Sebelum upload
Play pertama, buat dan backup upload keystore permanen, ubah `key.properties`,
lalu build AAB. Gradle kini menolak debug certificate pada build production
kecuali override beta diberikan secara eksplisit.
