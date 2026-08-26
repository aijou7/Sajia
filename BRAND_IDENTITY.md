# Sajia Brand Identity

## Brand Core

**Name:** Sajia
**Category:** Kasir dan operasional F&B
**Tagline:** Kasir restoran yang rapi, cepat, dan siap tumbuh.
**Short copy:** Kelola pesanan, meja, dan struk dalam satu alur.

Sajia adalah aplikasi operasional untuk restoran, kafe, dan outlet F&B yang butuh alur kasir cepat, pencatatan rapi, dan sinkronisasi data yang bisa diandalkan.

## Personality

- Hangat: terasa dekat dengan pemilik outlet dan kasir.
- Jelas: copy pendek, instruksi langsung, tidak bertele-tele.
- Gesit: interaksi harus terasa cepat dan ringan.
- Bisa dipercaya: tampilan bersih, angka mudah dibaca, status tidak ambigu.

## Logo

Logo Sajia memakai simbol cloche di atas piring untuk mewakili layanan F&B, dengan badge "Rp" untuk menandai fungsi kasir dan transaksi.

Primary mark tersedia di:

- `assets/images/sajia_app_icon.svg`
- `assets/images/sajia_app_icon.png`
- `lib/core/brand.dart` melalui widget `SajiaMark`

Aturan pemakaian:

- Gunakan mark penuh dengan badge untuk app icon, splash, login, dan onboarding.
- Gunakan mark tanpa badge untuk area kecil seperti top bar dan navigation affordance.
- Jangan mengganti badge "Rp" dengan ikon lain agar asosiasi kasir tetap kuat.
- Jaga clear space minimal 25% dari ukuran logo di semua sisi.

## Color System

| Token | Hex | Use |
| --- | --- | --- |
| Sajia Teal | `#356B66` | Primary buttons, progress, focus, and deliberate interaction accents |
| Deep Teal | `#285752` | Primary-button gradient only |
| Soft Teal | `#E7F1EF` | Rare brand moments; never a default card or frame color |
| Ink | `#111111` | Main text, selected labels, icons, and strong UI chrome |
| Muted Ink | `#626262` | Secondary text and inactive icons |
| Surface | `#F6F6F6` | App background |
| Soft Neutral | `#F1F1F1` | Selected surfaces and quiet icon backgrounds |
| Border | `#E0E0E0` | Cards, fields, dividers, and frames |
| Success Green | `#2F7D64` | Paid, success, and completed states only |
| Warning Amber | `#C57843` | Hold, warning, and pending-attention states only |
| Danger Red | `#C55252` | Delete, void, failed, and destructive states only |

## Typography

Primary typeface: Inter via Google Fonts.
Fallback: system sans-serif.

Usage:

- Page title: 18-28, weight 700-800.
- Section title: 14-18, weight 700.
- Body: 12-15, weight 400-600.
- Numbers and money: weight 700-800, use compact labels.

## UI Direction

- Keep screens dense, clean, and fast to scan.
- Prefer white surfaces on neutral gray backgrounds.
- Use rounded controls, but keep cards and panels practical.
- Treat Sajia Teal as an accent, not as the base color of the interface.
- Keep normal text black or gray; use white text only on dark or accent-filled controls.
- Keep frames, dividers, cards, fields, and default icon backgrounds neutral.
- Use the teal gradient only for primary calls to action. Use black gradients for high-emphasis information surfaces.
- For transaction states, color must map consistently: neutral active, green success, amber waiting, red failed/void.

## Product Packaging

Sajia should feel free to start, not locked before value is proven.

Free includes the core POS workflow:

- Unlimited products and categories.
- Cashier transactions.
- Receipt printing.
- One outlet on local/offline data.
- Manual local backup.

Pro is for larger operational needs:

- Cloud sync and cloud backup.
- Multi device.
- Multi outlet.
- Advanced reporting/export.
- Role controls, audit logs, and future scale features.

Principle: Free lets an outlet sell today. Pro helps a growing outlet control, sync, and scale.

## Voice And Copy

Use Indonesian that sounds helpful and natural.

Do:

- "Masukkan PIN"
- "Lihat Pesanan"
- "Sinkronisasi selesai"
- "Kelola pesanan, meja, dan struk dalam satu alur."

Avoid:

- Overly technical errors without guidance.
- Generic product names like "POS F&B" as the user-facing brand.
- Long instructional copy on operational screens.

## Brand Constants

Implementation source of truth:

- `lib/core/brand.dart` for name, tagline, colors, voice, and logo widget.
- `lib/core/theme.dart` maps brand colors into Flutter theme tokens.

When changing brand language or color tokens, update `AppBrand` first, then use those values in UI and metadata.
