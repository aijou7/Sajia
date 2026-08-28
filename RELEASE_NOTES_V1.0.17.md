# Sajia 1.0.17

Perbaikan sesi owner untuk fitur online:

- cek status paket, tambah cabang, dan checkout sekarang selalu mengirim token
  sesi email owner yang aktif ke layanan Sajia;
- bila token sesi sudah kedaluwarsa, aplikasi memperbarui sesi satu kali lalu
  mencoba ulang request secara otomatis;
- jika sesi benar-benar telah berakhir, aplikasi menampilkan arahan untuk login
  email owner kembali, bukan pesan sesi tidak valid yang membingungkan.

## Instalasi Android

- APK ditujukan untuk perangkat Android ARM64 dengan Android 8.0 atau lebih baru.
- Build ini adalah distribusi langsung GitHub, bukan build Google Play.
- Versi aplikasi: `1.0.17` (`versionCode 2018`).
- Pengguna v1.0.16 dapat memperbarui langsung tanpa uninstall.
