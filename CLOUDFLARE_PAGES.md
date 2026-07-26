# Deploy dashboard Sajia ke Cloudflare Pages

Cloudflare Pages menyediakan subdomain gratis, misalnya
`sajia-owner.pages.dev`. Domain sendiri bersifat opsional.

## Sebelum deploy

Dashboard owner yang sesungguhnya harus membaca data cabang dari Supabase dan
menggunakan autentikasi cloud. Jangan deploy service key Supabase atau secret
payment provider ke Flutter Web; browser hanya boleh menerima `SUPABASE_URL`
dan anon key.

Tambahkan domain Cloudflare Pages yang nanti diterima ke daftar **Redirect URLs**
dan daftar origin/CORS pada project Supabase.

## Status saat ini

Jangan menjalankan `flutter build web` dengan target default (`lib/main.dart`).
Target itu adalah aplikasi kasir native dan memakai SQLite melalui FFI/Drift,
Bluetooth printer, serta penyimpanan file perangkat. FFI tidak dapat dikompilasi
ke JavaScript, sehingga build web akan gagal dengan error `sqlite3_*` atau
`Only JS interop members may be external`.

Sebelum halaman ini dapat di-deploy, buat target Flutter Web khusus owner yang:

- hanya membaca data dari Supabase;
- tidak mengimpor Drift, SQLite, printer Bluetooth, backup file, atau halaman
  kasir native;
- memakai Supabase Auth dan RLS untuk membatasi data cabang.

## Build target owner (setelah target web dibuat)

Jalankan di root project:

```powershell
flutter pub get
flutter build web --target=lib/main_owner_web.dart --release `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY `
  --dart-define=ENABLE_CLOUD_SYNC=true
```

Hasil siap upload ada di `build/web`. File `web/_redirects` ikut dibawa ke hasil
build agar URL dashboard tidak 404 saat direfresh.

## Deploy pertama

1. Buat akun Cloudflare gratis dan buka **Workers & Pages**.
2. Buat project Pages bernama `sajia-owner`.
3. Pilih **Direct Upload** dan upload seluruh isi folder `build/web`.
4. Cloudflare akan memberi URL `https://sajia-owner.pages.dev`.
5. Masukkan URL tersebut ke konfigurasi Supabase seperti pada bagian sebelumnya.

## Update berikutnya

Ulangi perintah build, lalu upload isi `build/web` pada deployment baru. Setelah
repository dipublikasikan ke GitHub, deployment bisa diotomatisasi lewat GitHub
Actions agar setiap push menghasilkan preview/release.

## Jangan dilakukan

- Jangan mengunggah file `.env`, service-role key, Xendit/QRIS secret, atau
  database SQLite.
- Jangan memakai Cloudflare Pages sebagai backend atau webhook QRIS. Webhook dan
  rahasia pembayaran harus tinggal di Supabase Edge Function.
