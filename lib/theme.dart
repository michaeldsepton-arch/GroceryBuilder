import 'package:flutter/material.dart';

class BB {
  static const green900 = Color(0xFF173F30);
  static const green700 = Color(0xFF1F5A43);
  static const green500 = Color(0xFF3C7D5B);
  static const green100 = Color(0xFFDCEBDD);
  static const gold = Color(0xFFC9A45C);
  static const goldDark = Color(0xFF9C7A33);
  static const cream = Color(0xFFF7F2E6);
  static const card = Color(0xFFFFFCF5);
  static const tomato = Color(0xFFC8553D);
  static const pepper = Color(0xFFE8B93A);
  static const ink = Color(0xFF1B2A23);
  static const muted = Color(0xFF6B7A72);
}

TextStyle serif(double size, {FontWeight w = FontWeight.w700, Color? color}) =>
    TextStyle(
      fontFamily: 'Fraunces',
      fontSize: size,
      color: color ?? BB.green900,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      fontWeight: w,
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BB.green700,
    primary: BB.green700,
    onPrimary: Colors.white,
    secondary: BB.gold,
    surface: BB.cream,
    error: BB.tomato,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BB.cream,
    appBarTheme: AppBarTheme(
      backgroundColor: BB.cream,
      foregroundColor: BB.green900,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: serif(24),
    ),
    cardTheme: CardThemeData(
      color: BB.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: BB.green900.withValues(alpha: 0.07)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: BB.card,
      indicatorColor: BB.green100,
      labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BB.green900)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BB.card,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: BB.green900.withValues(alpha: 0.12))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: BB.green900.withValues(alpha: 0.12))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: BB.green700, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BB.green700,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: BB.card,
      selectedColor: BB.green100,
      side: BorderSide(color: BB.green900.withValues(alpha: 0.12)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(color: BB.green900, fontWeight: FontWeight.w600),
    ),
  );
}
