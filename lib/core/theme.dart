import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand.dart';

class AppTheme {
  // ── SAJIA BRAND COLORS ────────────────────────
  static const primary = AppBrand.primary;
  static const primaryDark = AppBrand.primaryDark;
  static const primaryDeep = AppBrand.primaryDeep;
  static const primaryBright = AppBrand.primaryBright;
  static const primaryLight = AppBrand.primaryLight;
  static const gold = AppBrand.gold;
  static const goldLight = AppBrand.goldLight;
  static const success = AppBrand.success;
  static const warning = AppBrand.warning;
  static const danger = AppBrand.danger;
  static const info = AppBrand.info;
  static const qris = primaryBright;
  static const revenue = gold;
  static const darkColor = Color(0xFF0F172A); // Malam Dark

  static const surface = Color(0xFFF4F8FB);
  static const surfaceWarm = Color(0xFFFAFCFE);
  static const borderColor = Color(0xFFE5E7EB);
  static const subtleBorder = Color(0xFFDDE7F0);
  static const cardBg = Colors.white;
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF667085);

  static const brandGradient = LinearGradient(
    colors: [primaryDeep, primary, primaryBright],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const payGradient = LinearGradient(
    colors: [Color(0xFF16A36D), Color(0xFF0E8F80)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get floatingShadow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.18),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ];

  // Status meja
  static const tableAvailable = Color(0xFF1A9E6A);
  static const tableOccupied = Color(0xFFDC2626);
  static const tableHold = Color(0xFFF59E0B);
  static const tableCleaning = Color(0xFF6B7280);

  // ── LIGHT THEME ───────────────────────────────
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      secondary: success,
      error: danger,
      surface: surfaceWarm,
      onSurface: textPrimary,
    ),
    textTheme: GoogleFonts.interTextTheme().apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    scaffoldBackgroundColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: borderColor),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: danger),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: primary,
      unselectedItemColor: Color(0xFF9CA3AF),
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: borderColor,
      thickness: 0.5,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: primaryLight,
      labelStyle: GoogleFonts.inter(fontSize: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: borderColor),
      ),
    ),
  );

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme:
        ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.dark),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  );
}

extension OrderStatusColor on String {
  Color get statusColor => switch (this) {
        'open' => AppTheme.primary,
        'in_kitchen' => AppTheme.info,
        'ready' => AppTheme.success,
        'paid' => const Color(0xFF6B7280),
        'hold' => AppTheme.warning,
        'void' => AppTheme.danger,
        _ => const Color(0xFF9CA3AF),
      };

  String get statusLabel => switch (this) {
        'open' => 'Buka',
        'in_kitchen' => 'Dapur',
        'ready' => 'Siap',
        'paid' => 'Lunas',
        'hold' => 'Hold',
        'void' => 'Void',
        _ => this,
      };
}
