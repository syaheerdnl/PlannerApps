import 'package:flutter/material.dart';

/// Every colour the app uses lives here, so the look can change in one place.
class AppColors {
  static const brand = Color(0xFF0E6B5C);
  static const brandDark = Color(0xFF0A4F43);
  static const brandTint = Color(0xFFE6F2EF);
  static const background = Color(0xFFF2F4F7);
  static const surface = Colors.white;
  static const ink = Color(0xFF1A1D21);
  static const muted = Color(0xFF5F6B7A);
  static const line = Color(0xFFE3E7EC);
  static const warnBg = Color(0xFFFFF1D6);
  static const warnFg = Color(0xFF7A4B00);
  static const dangerBg = Color(0xFFFDE7E4);
  static const dangerFg = Color(0xFF8F1D12);

  /// One colour per envelope, assigned by position so they stay the same.
  static const envelopes = [
    Color(0xFF2D5BA3),
    Color(0xFFB4531A),
    Color(0xFF6B4E9B),
    Color(0xFF0E6B5C),
    Color(0xFFA33A5B),
    Color(0xFF5F6B7A),
  ];

  static Color envelope(int index) => envelopes[index % envelopes.length];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, primary: AppColors.brand, surface: AppColors.surface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
    textTheme: ThemeData.light().textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.ink),
      titleTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: _border(AppColors.line),
      enabledBorder: _border(AppColors.line),
      focusedBorder: _border(AppColors.brand, 2),
      errorBorder: _border(AppColors.dangerFg),
      focusedErrorBorder: _border(AppColors.dangerFg, 2),
    ),
  );
}

OutlineInputBorder _border(Color color, [double width = 1]) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );
}
