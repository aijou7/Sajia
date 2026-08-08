# Setup Supabase Email OTP untuk Sajia

Aplikasi memakai `signInWithOtp()` untuk dua alur:

- Email baru / daftar bisnis: Supabase mengirim template **Confirm signup**.
- Email yang sudah terdaftar / pemulihan perangkat: Supabase mengirim template **Magic Link**.

Agar keduanya mengirim kode angka, buka Supabase Dashboard > Authentication > Email Templates dan ubah **kedua template** tersebut.

## Confirm signup

```html
<h2>Kode verifikasi pendaftaran Sajia</h2>
<p>Masukkan kode berikut ke aplikasi:</p>
<h1 style="font-size:32px;letter-spacing:8px">{{ .Token }}</h1>
<p>Kode ini hanya berlaku sekali. Jangan berikan kepada siapa pun.</p>
```

## Magic Link

```html
<h2>Kode login Sajia</h2>
<p>Masukkan kode berikut ke aplikasi:</p>
<h1 style="font-size:32px;letter-spacing:8px">{{ .Token }}</h1>
<p>Kode ini hanya berlaku sekali. Jangan berikan kepada siapa pun.</p>
```

Pastikan tidak ada `{{ .ConfirmationURL }}` di body HTML, tombol, fallback text, maupun bagian tersembunyi pada kedua template.

Setelah menyimpan template, tunggu minimal 60 detik sebelum meminta kode lagi. Uji pendaftaran dengan email yang benar-benar baru atau hapus user pengujian lama dari Authentication > Users terlebih dahulu.
