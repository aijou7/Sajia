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
  static const accent = AppBrand.accent;
  static const accentLight = AppBrand.accentLight;
  static const success = AppBrand.success;
  static const warning = AppBrand.warning;
  static const danger = AppBrand.danger;
  static const info = AppBrand.info;
  static const qris = primaryBright;
  static const revenue = accent;
  static const darkColor = Color(0xFF172321);

  static const surface = Color(0xFFF5F7F6);
  static const surfaceWarm = Color(0xFFFBFCFB);
  static const borderColor = Color(0xFFDCE5E2);
  static const subtleBorder = Color(0xFFD1DFDB);
  static const cardBg = Colors.white;
  static const textPrimary = Color(0xFF172321);
  static const textSecondary = Color(0xFF667470);

  // Satu skala ikon menjaga baseline dan bobot visual konsisten.
  static const iconCompact = 16.0;
  static const iconDefault = 22.0;
  static const iconProminent = 24.0;

  static const brandGradient = LinearGradient(
    colors: [primaryDeep, primary, primaryBright],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const payGradient = LinearGradient(
    colors: [Color(0xFF347A68), Color(0xFF285752)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF172321).withValues(alpha: 0.08),
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
  static const tableAvailable = success;
  static const tableOccupied = danger;
  static const tableHold = warning;
  static const tableCleaning = Color(0xFF73807C);

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
    iconTheme: const IconThemeData(
      size: iconDefault,
      color: textSecondary,
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
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: borderColor),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FAF9),
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
      prefixIconColor: textSecondary,
      suffixIconColor: textSecondary,
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: primary,
      unselectedItemColor: Color(0xFF8B9894),
      elevation: 0,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: iconDefault,
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
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
