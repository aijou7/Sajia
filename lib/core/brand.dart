import 'package:flutter/material.dart';

class AppBrand {
  /// Public product name. Keep the legacy package/database identifiers
  /// unchanged so existing installs can update in place.
  static const name = 'Kasata';
  static const legalName = 'Kasata';
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
  static const primary = Color(0xFF176B55);
  static const primaryDark = Color(0xFF10523F);
  static const primaryDeep = Color(0xFF123C30);
  static const primaryBright = Color(0xFF26846A);
  static const primaryLight = Color(0xFFEAF4EF);
  static const accent = primary;
  static const accentLight = primaryLight;
  static const success = Color(0xFF24734D);
  static const warning = Color(0xFF91600F);
  static const danger = Color(0xFFB83D42);
  static const info = Color(0xFF3567A1);
  static const ink = Color(0xFF191C1B);
  static const mutedInk = Color(0xFF626966);
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
    return Semantics(
      image: true,
      label: '${AppBrand.name} logo',
      child: Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundGradient == null
            ? (backgroundColor ?? AppBrand.primary)
            : null,
        gradient: backgroundGradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(painter: _KasataSymbolPainter(foregroundColor)),
      ),
    );
  }
}

/// Same geometry as the master SVG; stays sharp at every UI scale.
class _KasataSymbolPainter extends CustomPainter {
  const _KasataSymbolPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final paint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(14, 17, 9, 30),
          const Radius.circular(2)),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(28, 32)
        ..lineTo(41, 17)
        ..lineTo(52, 17)
        ..lineTo(39, 32)
        ..lineTo(52, 47)
        ..lineTo(41, 47)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KasataSymbolPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Logo utama Kasata untuk area yang cukup lebar.
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
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                  ),
                ),
                if (showDescriptor) ...[
                  SizedBox(height: markSize * 0.10),
                  Text(
                    AppBrand.descriptor,
                    style: TextStyle(
                      color: descriptorColor,
                      fontSize: descriptorFontSize,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
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
