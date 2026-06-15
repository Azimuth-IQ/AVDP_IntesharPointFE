import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';

/// Light+dark themes for the active session, seeded by the logged-in entity's
/// white-label brand colours (FR-28). Falls back to the default Inteshar
/// Sunburst palette before login or when the entity sets no colours.
final brandThemeProvider = Provider<({ThemeData light, ThemeData dark})>((ref) {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth is AuthAuthenticated) {
    final meta = auth.entity.meta;
    return buildBrandThemes(
      primaryHex: meta.primaryColor,
      secondaryHex: meta.secondaryColor,
    );
  }
  return buildBrandThemes();
});
