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

  static const primary = Color(0xFF1B6CA8);
  static const primaryDark = Color(0xFF0F4C7A);
  static const primaryDeep = Color(0xFF07395F);
  static const primaryBright = Color(0xFF2D9CDB);
  static const primaryLight = Color(0xFFE8F2FB);
  static const gold = Color(0xFFEF9F27);
  static const goldLight = Color(0xFFFFF5DE);
  static const success = Color(0xFF1A9E6A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF0EA5E9);
  static const ink = Color(0xFF101828);
  static const mutedInk = Color(0xFF667085);
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
