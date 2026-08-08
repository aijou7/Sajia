# Perbaikan POS Mobile — 6 Agustus 2026

## Perubahan

1. OTP registrasi Supabase
   - Email selalu dinormalisasi menjadi huruf kecil sebelum pengiriman dan verifikasi.
   - Mencegah request OTP ganda saat tombol masih memproses.
   - Kode OTP lama dibersihkan saat kirim ulang.
   - Verifikasi registrasi mendukung token `signup` dan `email` agar kompatibel dengan alur Supabase yang berbeda.
   - Pesan kesalahan OTP diperjelas.

2. Jumlah item di keranjang
   - Equality `CartItem` dan `Cart` sekarang memasukkan quantity serta seluruh state penting.
   - Tombol tambah/kurang memakai state quantity terbaru, bukan nilai lama dari widget.
   - Ditambahkan validasi index agar tidak terjadi error ketika item sudah berubah atau terhapus.

3. Hapus pengeluaran pada laporan keuangan
   - Owner mendapat tombol hapus pada daftar pengeluaran di Dashboard Bisnis > Laba Rugi.
   - Ada dialog konfirmasi sebelum penghapusan.
   - Penghapusan dilakukan secara lokal dan masuk antrean sinkronisasi untuk dihapus dari Supabase saat Cloud aktif dan perangkat online.
   - Manager hanya dapat melihat, tidak dapat menghapus.

4. Profil dan logout
   - Chip profil di kanan atas halaman Kasir sekarang dapat ditekan.
   - Menampilkan nama, role, dan tombol logout.
   - Logout dapat digunakan Owner, Manager, dan Kasir.
   - Keranjang dikosongkan saat logout agar pesanan user sebelumnya tidak terbawa.

## File utama yang diubah

- `lib/core/onboarding_service.dart`
- `lib/features/onboarding/onboarding_page.dart`
- `lib/domain/entities/entities.dart`
- `lib/core/providers.dart`
- `lib/features/cashier/cart_panel.dart`
- `lib/features/cashier/cashier_page.dart`
- `lib/data/local/daos/finance_dao.dart`
- `lib/data/sync/sync_service.dart`
- `lib/features/dashboard/business_dashboard_page.dart`
- `lib/features/settings/settings_page.dart`
- `test/cart_notifier_test.dart`

## Pengujian yang perlu dilakukan di komputer pengembang

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
```

Uji manual:

- Registrasi memakai email baru dan OTP terbaru.
- Login/pemulihan memakai email yang sudah terdaftar.
- Tambahkan menu yang sama, lalu tekan `+` beberapa kali dan `-` sampai item hilang.
- Login sebagai owner, buat pengeluaran, lalu hapus dari tab Laba Rugi.
- Login sebagai manager/kasir, tekan profil kanan atas, lalu logout.

## Catatan keamanan

`android/key.properties`, `android/local.properties`, file build, APK, dan cache tidak disertakan dalam arsip hasil perbaikan. Gunakan kembali file signing lokal milik Anda hanya di komputer pengembang dan jangan mengunggahnya ke repositori atau chat.

## Perbaikan lanjutan — menu, stok, dan laporan kategori

5. Hapus produk dan kategori
   - Owner mendapat menu `Hapus produk` pada tombol tiga titik di daftar menu.
   - Ada dialog konfirmasi sebelum produk dihapus.
   - Penghapusan produk dan variannya dimasukkan ke antrean sinkronisasi Supabase.
   - Owner juga dapat menghapus kategori; produk di dalam kategori tersebut tetap dipertahankan dan dipindahkan ke `Tanpa kategori`.

6. Pelacakan stok
   - Form tambah/edit produk sekarang menyediakan `Stok Awal / Sisa Stok` dan batas `Peringatan Stok Menipis` ketika `Lacak Stok` diaktifkan.
   - Daftar menu pengelolaan menampilkan sisa stok dan indikator stok menipis.
   - Tombol `Atur stok` tersedia dari menu aksi produk.
   - Halaman kasir menampilkan stok dan menonaktifkan produk yang habis.
   - Jumlah pesanan tidak dapat melebihi stok yang tersedia.
   - Stok divalidasi ulang ketika pembayaran diproses dan berkurang otomatis setelah transaksi berhasil disimpan.

7. Laporan per kategori
   - Halaman laporan sekarang memiliki tab ketiga: `Kategori`.
   - Setiap kategori menampilkan jumlah produk, kuantitas terjual, omzet, dan persentase kontribusi.
   - Ekspor PDF laporan sekarang memuat tabel `Penjualan per Kategori`.

## File tambahan yang diubah

- `lib/data/local/daos/product_dao.dart`
- `lib/data/local/daos/order_dao.dart`
- `lib/features/menu/menu_page.dart`
- `lib/features/cashier/payment_sheet.dart`
- `lib/features/reports/reports_page.dart`
- `pubspec.yaml` (`1.0.6+7`)

Uji manual tambahan:

- Login sebagai owner, buka Menu, tekan tombol tiga titik, lalu hapus salah satu produk percobaan.
- Aktifkan `Lacak Stok`, isi stok 2, lalu tambahkan produk maksimal dua kali di kasir.
- Selesaikan pembayaran dan pastikan sisa stok berkurang.
- Buka Laporan > Kategori dan cek kesesuaian omzet dengan transaksi.
- Ekspor PDF dan pastikan bagian `Penjualan per Kategori` tampil.


## Koreksi OTP registrasi — 7 Agustus 2026

8. Verifikasi email OTP diseragamkan
   - Registrasi baru dan login akun lama sekarang diverifikasi dengan `OtpType.email`.
   - Fallback `OtpType.signup` dihapus karena tipe tersebut sudah deprecated untuk email OTP dan dapat menghasilkan pesan kedaluwarsa/invalid yang menyesatkan.
   - Catatan penting: email pertama untuk alamat baru memakai template Supabase **Confirm signup**, sedangkan login alamat lama memakai template **Magic Link**. Keduanya harus menggunakan `{{ .Token }}` dan tidak boleh memakai `{{ .ConfirmationURL }}` bila aplikasi meminta kode OTP.

Versi aplikasi: `1.0.7+8`.
