# Sajia 1.0.21 (build 2023)

Perbaikan respons simpan menu untuk pengguna Cloud.

- Produk, stok, kategori, urutan kategori, dan penghapusan menu langsung
  selesai setelah tersimpan aman di database lokal.
- Sinkronisasi Cloud tetap langsung diminta setelah perubahan, tetapi berjalan
  di belakang layar sehingga form tidak menunggu siklus push/pull penuh.
- Retry otomatis tetap berjalan setiap satu menit dan saat koneksi internet
  kembali tersedia.
- Sinkronisasi transaksi, shift, stok, dan laporan lintas cabang tidak diubah
  menjadi interval per jam atau per hari.

## Instalasi Android

- Versi tampilan tetap `1.0.21`; build Android diperbarui ke `2023` agar dapat
  dipasang sebagai pembaruan.
- Android 8.0 atau lebih baru.
- Pilih APK **V8A 64-bit** untuk kebanyakan perangkat baru.
- Pilih APK **V7A 32-bit** untuk tablet atau ponsel lama yang 32-bit.
