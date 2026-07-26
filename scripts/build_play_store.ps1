$ErrorActionPreference = "Stop"

if (!(Test-Path "key.properties")) {
  throw "key.properties belum ada. Jalankan scripts/create_upload_keystore.ps1 lalu isi key.properties dulu."
}

flutter build appbundle --release --dart-define=SAJIA_DISTRIBUTION=play

Write-Host ""
Write-Host "AAB siap upload:"
Write-Host "build/app/outputs/bundle/release/app-release.aab"
