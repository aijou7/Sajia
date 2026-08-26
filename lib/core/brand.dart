import 'package:flutter/material.dart';

class AppBrand {
  static const name = 'Sajia';
  static const legalName = 'Sajia';
  static const descriptor = 'Kasir & Operasional F&B';
  static const tagline = 'Kasir restoran yang rapi, cepat, dan siap tumbuh.';
  static const shortTagline =
      'Kelola pesanan, meja, dan struk dalam satu alur.';

  static const voice = 'Hangat, jelas, gesit, dan bisa dipercaya.';
  static const promise =
      'Membantu outlet F&B melayani pelanggan lebih cepat tanpa kehilangan kendali operasional.';

  static const logoAsset = 'assets/images/sajia_app_icon.png';

  // Warna brand tetap tersedia untuk logo dan aksen interaksi. UI utama
  // memakai tinta netral agar warna ini tidak menyebar ke teks dan frame.
  static const primary = Color(0xFF356B66);
  static const primaryDark = Color(0xFF285752);
  static const primaryDeep = Color(0xFF1D403D);
  static const primaryBright = Color(0xFF6F9E98);
  static const primaryLight = Color(0xFFE7F1EF);
  static const accent = Color(0xFF746FA8);
  static const accentLight = Color(0xFFF0EEF8);
  static const success = Color(0xFF2F7D64);
  static const warning = Color(0xFFC57843);
  static const danger = Color(0xFFC55252);
  static const info = Color(0xFF557FA3);
  static const ink = Color(0xFF111111);
  static const mutedInk = Color(0xFF626262);
}

class SajiaMark extends StatelessWidget {
  final double size;
  final double radius;
  final bool showBadge;
  final Color? backgroundColor;
  final Gradient? backgroundGradient;
  final Color foregroundColor;
  final EdgeInsetsGeometry padding;

  const SajiaMark({
    super.key,
    this.size = 76,
    this.radius = 24,
    this.showBadge = true,
    this.backgroundColor,
    this.backgroundGradient,
    this.foregroundColor = Colors.white,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundGradient == null ? backgroundColor : null,
        gradient: backgroundGradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          AppBrand.logoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          semanticLabel: '${AppBrand.name} logo',
          errorBuilder: (_, __, ___) => ColoredBox(
            color: backgroundColor ?? AppBrand.primary,
            child: Center(
              child: Text(
                AppBrand.name.characters.first,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo utama Sajia untuk area yang cukup lebar.
///
/// Ikon launcher sengaja tetap berupa simbol agar terbaca pada ukuran kecil,
/// sedangkan lockup ini menyatukan simbol, wordmark, dan descriptor merek.
class SajiaLogoLockup extends StatelessWidget {
  final double markSize;
  final double markRadius;
  final double gap;
  final double nameFontSize;
  final double descriptorFontSize;
  final bool showDescriptor;
  final Color textColor;
  final Color descriptorColor;
  final Color? markBackgroundColor;
  final Gradient? markBackgroundGradient;

  const SajiaLogoLockup({
    super.key,
    this.markSize = 56,
    this.markRadius = 18,
    this.gap = 14,
    this.nameFontSize = 28,
    this.descriptorFontSize = 11,
    this.showDescriptor = true,
    this.textColor = AppBrand.ink,
    this.descriptorColor = AppBrand.mutedInk,
    this.markBackgroundColor,
    this.markBackgroundGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: showDescriptor
          ? '${AppBrand.name}, ${AppBrand.descriptor}'
          : AppBrand.name,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SajiaMark(
              size: markSize,
              radius: markRadius,
              backgroundColor: markBackgroundColor,
              backgroundGradient: markBackgroundGradient,
            ),
          ),
          SizedBox(width: gap),
          ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppBrand.name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: nameFontSize,
                    height: 0.94,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                if (showDescriptor) ...[
                  SizedBox(height: markSize * 0.10),
                  Text(
                    AppBrand.descriptor.toUpperCase(),
                    style: TextStyle(
                      color: descriptorColor,
                      fontSize: descriptorFontSize,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.75,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
