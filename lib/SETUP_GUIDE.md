# SETUP GUIDE — POS F&B Flutter Project

## MASALAH YANG TERJADI

1. `flutter run -d chrome` → SALAH. Package kita tidak support web.
   Target kita adalah Android (emulator atau device fisik).

2. File-file baru belum di-copy ke struktur folder yang benar di project lo.

---

## LANGKAH 1 — Struktur folder yang harus lo buat

Di dalam folder project Flutter lo (misal `C:\Users\aijou7\pos_mobile\`),
buat folder-folder ini kalau belum ada:

```
lib/
  core/
  data/
    local/
      tables/
      daos/
    sync/
  domain/
    entities/
  features/
    cashier/
    menu/
    orders/
    reports/
    settings/
  shared/
    widgets/
```

### Command PowerShell (jalankan di root project):
```powershell
cd C:\Users\aijou7\pos_mobile

New-Item -ItemType Directory -Force -Path lib\core
New-Item -ItemType Directory -Force -Path lib\data\local\tables
New-Item -ItemType Directory -Force -Path lib\data\local\daos
New-Item -ItemType Directory -Force -Path lib\data\sync
New-Item -ItemType Directory -Force -Path lib\domain\entities
New-Item -ItemType Directory -Force -Path lib\features\cashier
New-Item -ItemType Directory -Force -Path lib\features\menu
New-Item -ItemType Directory -Force -Path lib\features\orders
New-Item -ItemType Directory -Force -Path lib\features\reports
New-Item -ItemType Directory -Force -Path lib\features\settings
New-Item -ItemType Directory -Force -Path lib\shared\widgets
New-Item -ItemType Directory -Force -Path assets\images
New-Item -ItemType Directory -Force -Path assets\fonts
```

---

## LANGKAH 2 — Copy file-file dari output ke project lo

Dari folder `pos_fnb` yang sudah didownload, copy file berikut:

| File dari pos_fnb/                              | Copy ke project lo/                              |
|-------------------------------------------------|--------------------------------------------------|
| pubspec.yaml                                    | pubspec.yaml (REPLACE yang lama)                 |
| lib/main.dart                                   | lib/main.dart (REPLACE)                          |
| lib/core/theme.dart                             | lib/core/theme.dart                              |
| lib/core/utils.dart                             | lib/core/utils.dart                              |
| lib/core/providers.dart                         | lib/core/providers.dart                          |
| lib/core/router.dart                            | lib/core/router.dart                             |
| lib/data/local/tables/app_tables.dart           | lib/data/local/tables/app_tables.dart            |
| lib/data/local/app_database.dart               | lib/data/local/app_database.dart                 |
| lib/data/local/daos/product_dao.dart           | lib/data/local/daos/product_dao.dart             |
| lib/data/local/daos/order_dao.dart             | lib/data/local/daos/order_dao.dart               |
| lib/data/local/daos/session_dao.dart           | lib/data/local/daos/session_dao.dart             |
| lib/data/local/daos/sync_dao.dart              | lib/data/local/daos/sync_dao.dart                |
| lib/data/sync/sync_service.dart                | lib/data/sync/sync_service.dart                  |
| lib/domain/entities/entities.dart              | lib/domain/entities/entities.dart                |

---

## LANGKAH 3 — Ganti nama package di pubspec.yaml

Buka pubspec.yaml, pastikan baris `name:` sesuai nama project lo:

```yaml
name: pos_mobile   # <-- sesuaikan dengan nama project lo
```

Cek nama project lo di pubspec.yaml yang lama. Kalau namanya `pos_mobile`,
berarti semua import `package:pos_mobile/...` harus diganti `package:pos_mobile/...`.

Cara cepat: di VS Code, Ctrl+Shift+H (Find & Replace All):
- Find:    package:pos_mobile
- Replace: package:pos_mobile   ← nama project lo

---

## LANGKAH 4 — Supabase setup (sementara pakai dummy dulu)

Di `lib/main.dart`, ganti bagian Supabase.initialize dengan:

```dart
await Supabase.initialize(
  url: 'https://placeholder.supabase.co',      // ganti nanti
  anonKey: 'placeholder-key',                  // ganti nanti
);
```

Ini biar bisa run dulu tanpa error Supabase. Nanti ganti setelah buat project di supabase.com.

---

## LANGKAH 5 — flutter pub get + code generation

```powershell
# Di root project:
flutter pub get

# Generate kode Drift (WAJIB — tanpa ini DB tidak bisa compile):
dart run build_runner build --delete-conflicting-outputs
```

Build runner akan generate file `.g.dart` untuk semua DAO dan database.
Tunggu sampai selesai (~1-2 menit).

---

## LANGKAH 6 — Run di Android (BUKAN Chrome)

```powershell
# Pastikan emulator Android sudah jalan di Android Studio
# atau sambungkan device fisik via USB (aktifkan USB Debugging)

# Cek device yang tersedia:
flutter devices

# Run di Android:
flutter run -d android
# atau kalau ada emulator:
flutter run -d emulator-5554
```

JANGAN pakai `-d chrome` — package Drift, bluetooth_print, local_auth
tidak support web.

---

## LANGKAH 7 — Kalau masih error setelah semua langkah di atas

Error yang mungkin muncul dan solusinya:

### "Target of URI doesn't exist" / file not found
→ Pastikan semua file sudah di-copy ke lokasi yang benar (lihat tabel di Langkah 2)

### "Expected a file name" / part of error di .g.dart
→ Jalankan lagi: `dart run build_runner build --delete-conflicting-outputs`
   File .g.dart belum di-generate.

### "Package not found"
→ Jalankan `flutter pub get` lagi setelah pastikan pubspec.yaml sudah di-replace.

### MinSdkVersion error
→ Buka `android/app/build.gradle`, set:
```gradle
defaultConfig {
    minSdkVersion 21    // minimum untuk Drift + Supabase
    ...
}
```

### Bluetooth permission error (saat compile)
→ Di `android/app/src/main/AndroidManifest.xml`, tambahkan:
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
```

---

## CHECKLIST

- [ ] Folder struktur sudah dibuat
- [ ] Semua file sudah di-copy
- [ ] Nama package sudah disesuaikan di pubspec.yaml
- [ ] `flutter pub get` berhasil
- [ ] `dart run build_runner build` berhasil (ada file .g.dart)
- [ ] Run pakai `-d android`, bukan `-d chrome`
- [ ] App muncul di emulator/device (placeholder pages)
