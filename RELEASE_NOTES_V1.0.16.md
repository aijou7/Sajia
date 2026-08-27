# Sajia 1.0.16

Pembaruan recovery akun dan pengalaman startup:

- owner yang sudah memverifikasi email dapat membuat PIN baru saat PIN lama belum tersimpan di cloud;
- pemulihan perangkat tidak lagi mewajibkan akses ke perangkat lama;
- PIN recovery disimpan ke perangkat dan cloud sebelum onboarding diselesaikan;
- data outlet, menu, dan transaksi yang sudah ada tetap dipertahankan selama recovery;
- splash screen baru memakai animasi masuk, pulse logo, dan indikator loading yang lebih halus;
- startup menampilkan pilihan coba lagi jika inisialisasi gagal, bukan berhenti pada layar statis.

## Instalasi Android

- APK ditujukan untuk perangkat Android ARM64 dengan Android 8.0 atau lebih baru.
- Build ini adalah distribusi langsung GitHub, bukan build Google Play.
- Versi aplikasi: `1.0.16` (`versionCode 2017`).
- Pengguna v1.0.15 dapat memperbarui langsung tanpa uninstall.

## Recovery perangkat baru

Pilih **Masuk / ganti perangkat**, verifikasi email owner dengan OTP, lalu buat
PIN owner baru jika akun cloud belum memiliki PIN. Perangkat lama tidak lagi
diperlukan untuk menyelesaikan recovery tersebut.
