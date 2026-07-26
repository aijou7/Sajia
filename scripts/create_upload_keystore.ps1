param(
  [string]$Alias = "sajia_upload",
  [string]$KeystorePath = "android/app/sajia-upload-key.jks"
)

$ErrorActionPreference = "Stop"

if (Test-Path $KeystorePath) {
  throw "Keystore already exists: $KeystorePath"
}

Write-Host "Membuat upload keystore untuk Google Play..."
Write-Host "Simpan password dengan aman. Jangan commit key.properties atau file .jks."

keytool -genkeypair `
  -v `
  -keystore $KeystorePath `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias $Alias `
  -dname "CN=Aijou Teknologi Digital, OU=Sajia, O=Aijou Teknologi Digital, L=Jakarta, ST=DKI Jakarta, C=ID"

Write-Host ""
Write-Host "Keystore dibuat: $KeystorePath"
Write-Host "Copy key.properties.example menjadi key.properties, lalu isi password yang barusan kamu buat."
