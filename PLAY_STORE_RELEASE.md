# Sajia Google Play Release Checklist

## Package

- Application ID: `id.aksaldev.sajia`
- Build Play Store wajib pakai channel:
  `--dart-define=SAJIA_DISTRIBUTION=play`
- Build resmi yang memakai Play Integrity juga wajib membawa Google Cloud project number:
  `--dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=ISI_PROJECT_NUMBER`

## Signing

Jangan upload build yang ditandatangani debug key.

1. Buat upload keystore:

   ```powershell
   keytool -genkeypair -v -keystore android/app/sajia-upload-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias sajia_upload
   ```

2. Copy `key.properties.example` ke `key.properties`.
3. Isi password yang dipakai saat generate keystore.
4. Simpan `key.properties` dan `.jks` baik-baik. File ini sudah masuk `.gitignore`.

## Build untuk Google Play

```powershell
flutter build appbundle --release `
  --dart-define=SAJIA_DISTRIBUTION=play `
  --dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=ISI_PROJECT_NUMBER
```

Output:

`build/app/outputs/bundle/release/app-release.aab`

## Payment policy

Build Google Play tidak menampilkan tombol beli Pro/Cloud lewat Midtrans.
Versi Play hanya menampilkan status lisensi dan tombol cek status lisensi.

Untuk distribusi luar Play Store / direct APK, build tanpa define `SAJIA_DISTRIBUTION=play`
masih bisa memakai checkout eksternal.

## Play Integrity + server entitlement

Entitlement Pro/Cloud tetap dianggap valid hanya dari server Supabase, bukan dari nilai lokal
aplikasi. Untuk mengaktifkan hard check integritas saat checkout payment, set secrets Edge
Function:

```powershell
supabase secrets set PLAY_INTEGRITY_PACKAGE_NAME=id.aksaldev.sajia
supabase secrets set PLAY_INTEGRITY_ENFORCE_PAYMENT=true
supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON='ISI_JSON_SERVICE_ACCOUNT_GOOGLE'
```

Opsional tapi disarankan setelah signing release final:

```powershell
supabase secrets set PLAY_INTEGRITY_CERT_SHA256=ISI_SHA256_CERT_RELEASE
supabase secrets set PLAY_INTEGRITY_ALLOWED_DEVICE_VERDICTS=MEETS_DEVICE_INTEGRITY,MEETS_STRONG_INTEGRITY
```

Deploy ulang function terkait setelah secrets siap:

```powershell
supabase functions deploy create-plan-checkout
supabase functions deploy verify-app-integrity
```

Saat development, `PLAY_INTEGRITY_ENFORCE_PAYMENT=false` dulu supaya checkout bisa dites di
APK lokal/debug.

## Local database encryption

Database lokal `pos_fnb.db` sekarang dibuka dengan SQLite3MultipleCiphers melalui `sqlite3mc`.
Key dibuat otomatis dan disimpan di secure storage perangkat. Kalau user clear app data /
ganti perangkat, key lokal hilang; restore data harus lewat backup terenkripsi Sajia.

## Console assets yang perlu disiapkan

- Privacy Policy URL.
- Data Safety form.
- App access / akun demo owner untuk reviewer.
- Icon 512x512.
- Feature graphic 1024x500.
- Screenshot HP.
- Deklarasi permission Bluetooth dan notification sesuai fitur printer/notifikasi.
