# Sajia 1.0.9

Hotfix isolasi akun owner:

- pencarian PIN hanya dilakukan pada outlet milik Auth user yang sedang aktif;
- pergantian email owner membersihkan data lokal akun sebelumnya sebelum
  pemulihan atau sinkronisasi berjalan;
- scope outlet terverifikasi disimpan bersama Supabase Auth user ID, bukan saat
  email baru sekadar meminta OTP;
- sync memverifikasi kepemilikan outlet sebelum mendorong data lokal;
- perangkat lama yang sudah telanjur menyimpan dua owner akan memangkas data
  outlet yang bukan milik akun aktif saat kembali online;
- antrean sync lama dibuang saat account switch untuk mencegah mutasi bisnis
  sebelumnya terkirim ke owner baru.
- daftar staff, validasi PIN baru, dan ganti PIN juga hanya membandingkan user
  di dalam scope outlet owner yang sedang terverifikasi.

Verifikasi: `flutter analyze` tanpa issue dan 33 test lulus, termasuk test dua
owner berbeda yang menggunakan angka PIN sama tanpa saling berbenturan.

Artefak Android beta:

- file: `output/release-v1.0.9/Sajia-v1.0.9-arm64.apk`;
- package: `id.aksaldev.sajia`;
- version: `1.0.9` (`versionCode 2010`);
- ukuran: 23.989.402 byte (22,88 MiB);
- SHA-256: `DCB631087D491FFADC6D10531672376EE7E6120544FF15A2046842C392B75C15`.

APK ini ditandatangani sertifikat debug untuk distribusi beta GitHub. Gunakan
upload/release keystore permanen sebelum mengirim AAB ke Google Play.
