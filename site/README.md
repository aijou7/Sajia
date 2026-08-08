# Sajia Official Site

Static landing page untuk download dan positioning resmi Sajia.

## Preview lokal

Buka `site/index.html` langsung di browser, atau serve folder ini dengan static server.

## Download APK

Tombol download mengarah ke:

```text
https://github.com/aijou7/Sajia/releases/download/V1.0.7/Sajia-v1.0.7-arm64.apk
```

Upload APK sebagai GitHub Release asset dengan nama `Sajia-v1.0.4-arm64.apk`.
File APK memakai build `arm64-v8a` yang lebih kecil untuk Android modern.

Build APK kecil:

```text
flutter build apk --release --split-per-abi --no-pub
```

Lalu upload file ini sebagai asset release bernama `Sajia-v1.0.4-arm64.apk`:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Kalau tombol download 404 setelah upload ke hosting, cek ini:

1. Pastikan tag GitHub Release `V1.0.4` sudah diterbitkan.
2. Pastikan aset bernama persis `Sajia-v1.0.4-arm64.apk`.
3. Pastikan tombol download memakai URL aset GitHub Release yang sama.

## Health check / idle prevention

Upload `health.html` bersama file website lain. Setelah subdomain aktif,
pakai layanan monitor seperti UptimeRobot atau cron-job.org untuk ping:

```text
https://domain-sajia-kamu/health.html
```

Interval aman untuk hosting gratis: 6-12 jam sekali. Hindari ping terlalu
sering supaya tidak menghabiskan limit hit harian.
