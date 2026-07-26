# CHECKLIST REBRAND → SAJIA
# =============================================
# Copy semua file dari output ini ke project lo

## FILE YANG HARUS DI-REPLACE:
# ─────────────────────────────────────────────
# lib/main.dart                          ← REPLACE
# lib/core/theme.dart                    ← REPLACE
# lib/features/auth/pin_login_page.dart  ← REPLACE
# lib/features/cashier/cashier_page.dart ← REPLACE
# lib/features/shared/main_scaffold.dart ← REPLACE

## ANDROID:
# ─────────────────────────────────────────────
# android/app/src/main/AndroidManifest.xml
#   → Ganti android:label="pos_mobile" jadi android:label="Sajia"
#   (lihat file AndroidManifest.xml sebagai referensi)

## APP ICON:
# ─────────────────────────────────────────────
# 1. Buka app_icon.svg di browser untuk preview
# 2. Export ke PNG 1024x1024:
#    - Upload SVG ke https://svgtopng.com atau https://cloudconvert.com
#    - Download PNG 1024x1024
#    - Simpan ke: assets/icon/app_icon.png
# 3. Tambah di pubspec.yaml (dev_dependencies):
#    flutter_launcher_icons: ^0.13.1
# 4. Tambah config di pubspec.yaml (paling bawah):
#    flutter_launcher_icons:
#      android: true
#      ios: false
#      image_path: "assets/icon/app_icon.png"
#      min_sdk_android: 21
#      adaptive_icon_background: "#1B6CA8"
#      adaptive_icon_foreground: "assets/icon/app_icon.png"
# 5. Jalankan:
#    flutter pub get
#    dart run flutter_launcher_icons

## CARI & GANTI TEKS DI SELURUH PROJECT:
# ─────────────────────────────────────────────
# Di VS Code: Ctrl+Shift+H (Search & Replace across files)
#
# "POS F&B"  →  "Sajia"
# "pos_fnb"  →  "sajia"
# "POS"      →  "Sajia"  (hati-hati, cek satu per satu)

## SETELAH SEMUA SELESAI:
# ─────────────────────────────────────────────
# flutter run -d emulator-5554
