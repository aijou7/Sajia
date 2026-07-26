# Sajia

Sajia is a cashier and F&B operations app for outlets that need fast orders, clear table flow, reliable receipts, and offline-first local storage.

Brand guidance lives in [`BRAND_IDENTITY.md`](BRAND_IDENTITY.md). The in-app brand constants and logo widget live in `lib/core/brand.dart`.

## Stack

- Flutter + Riverpod
- Drift + SQLite for local data
- Supabase for cloud sync and license activation
- GoRouter for navigation
- ESC/POS Bluetooth/Wi-Fi receipt printing

## Setup

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Supabase can be configured with Dart defines:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

## Owner dashboard web

Dashboard owner dapat dipublikasikan gratis menggunakan Cloudflare Pages di
subdomain `*.pages.dev`; domain sendiri tidak diperlukan. Panduan build dan
deploy tersedia di [`CLOUDFLARE_PAGES.md`](CLOUDFLARE_PAGES.md). Dashboard web
harus memakai target khusus owner, bukan `lib/main.dart` aplikasi kasir native.

## Verification

```bash
flutter test --no-pub
flutter analyze --no-pub
```

## Official Site

Static website resmi Sajia ada di `site/`.

APK publik disimpan sebagai GitHub Release, bukan di dalam repository. Untuk
membuat APK ARM64 Android modern:

```bash
flutter build apk --release --split-per-abi --no-pub
```

## Pro payments

Sajia Pro memakai checkout Midtrans melalui Supabase Edge Functions. Ikuti
[`supabase/README.md`](supabase/README.md) untuk migration, environment secret,
deploy function, dan webhook Midtrans. Server Key Midtrans tidak boleh masuk ke
APK.

## Notes

- The app restores the current outlet from local preferences after onboarding.
- Receipt tax and service charge are read from outlet settings.
- Hak akses owner, manager, dan kasir dibatasi per outlet melalui RLS dan
  fungsi server.
- Status Pro/Cloud berasal dari entitlement server; aplikasi lokal bukan sumber
  kebenaran lisensi.
