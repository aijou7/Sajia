import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand.dart';

class AppTheme {
  // ── NEUTRAL UI + BRAND ACCENT ─────────────────
  // Warna Sajia dipakai sebagai aksen interaksi, bukan sebagai warna chrome,
  // teks, frame, atau permukaan aplikasi.
  static const action = AppBrand.primary;
  static const actionDark = AppBrand.primaryDark;
  static const actionBright = AppBrand.primaryBright;
  static const actionSoft = AppBrand.primaryLight;

  static const surface = Color(0xFFF6F6F6);
  static const surfaceWarm = Colors.white;
  static const neutralSoft = Color(0xFFF1F1F1);
  static const borderColor = Color(0xFFE0E0E0);
  static const subtleBorder = Color(0xFFE7E7E7);
  static const cardBg = Colors.white;
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF626262);

  // Alias lama sengaja dinetralkan agar komponen yang sebelumnya mewarnai
  // teks, ikon, kartu, dan frame otomatis kembali ke hitam/abu. Gunakan
  // `action*` bila warna brand memang dibutuhkan sebagai aksen interaksi.
  static const primary = textPrimary;
  static const primaryDark = textPrimary;
  static const primaryDeep = textPrimary;
  static const primaryBright = textSecondary;
  static const primaryLight = neutralSoft;
  static const accent = textPrimary;
  static const accentLight = neutralSoft;
  static const success = AppBrand.success;
  static const warning = AppBrand.warning;
  static const danger = AppBrand.danger;
  static const info = AppBrand.info;
  static const qris = actionBright;
  static const revenue = textPrimary;
  static const darkColor = textPrimary;

  // Satu skala ikon menjaga baseline dan bobot visual konsisten.
  static const iconCompact = 16.0;
  static const iconDefault = 22.0;
  static const iconProminent = 24.0;

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF111111), Color(0xFF292929)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const actionGradient = LinearGradient(
    colors: [action, actionDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const payGradient = LinearGradient(
    colors: [action, actionDark],
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
          color: textPrimary.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 12),
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
    colorScheme: const ColorScheme.light(
      primary: action,
      onPrimary: Colors.white,
      primaryContainer: neutralSoft,
      onPrimaryContainer: textPrimary,
      secondary: textPrimary,
      onSecondary: Colors.white,
      secondaryContainer: neutralSoft,
      onSecondaryContainer: textPrimary,
      tertiary: textSecondary,
      onTertiary: Colors.white,
      tertiaryContainer: neutralSoft,
      onTertiaryContainer: textPrimary,
      error: danger,
      onError: Colors.white,
      errorContainer: Color(0xFFFFEAEA),
      onErrorContainer: danger,
      surface: surfaceWarm,
      onSurface: textPrimary,
      surfaceTint: Colors.transparent,
      outline: borderColor,
      outlineVariant: subtleBorder,
      shadow: Colors.black,
      scrim: Colors.black,
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
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
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
        backgroundColor: action,
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
      fillColor: const Color(0xFFF8F9F8),
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
        foregroundColor: textPrimary,
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: borderColor),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: action,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: action,
      foregroundColor: Colors.white,
      elevation: 0,
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
      selectedColor: neutralSoft,
      labelStyle: GoogleFonts.inter(fontSize: 12, color: textPrimary),
      secondaryLabelStyle:
          GoogleFonts.inter(fontSize: 12, color: textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: borderColor),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: textPrimary,
      unselectedLabelColor: textSecondary,
      indicatorColor: textPrimary,
      dividerColor: borderColor,
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: textSecondary,
      textColor: textPrimary,
      selectedColor: textPrimary,
      selectedTileColor: neutralSoft,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: action,
      linearTrackColor: neutralSoft,
      circularTrackColor: neutralSoft,
    ),
  );

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme:
        ColorScheme.fromSeed(seedColor: action, brightness: Brightness.dark),
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
