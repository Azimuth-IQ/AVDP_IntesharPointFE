import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _seed = Color(0xFF0E3A6B);

ThemeData _build(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: GoogleFonts.cairoTextTheme(
      b == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

final intesharLightTheme = _build(Brightness.light);
final intesharDarkTheme = _build(Brightness.dark);
