import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';

/// Locale codes written in a cursive script, where letter-spacing breaks the
/// joins between letters (UX-141). Arabic is this product's primary locale.
const Set<String> kCursiveLanguageCodes = {'ar', 'fa', 'ur'};

/// Light+dark themes for the active session, seeded by the logged-in entity's
/// white-label brand colours (FR-28). Falls back to the default Inteshar
/// Sunburst palette before login or when the entity sets no colours.
///
/// UX-141: the themes are also locale-dependent now — a cursive locale drops
/// every baked letter-spacing, so switching language rebuilds them.
final brandThemeProvider = Provider<({ThemeData light, ThemeData dark})>((ref) {
  final cursive = kCursiveLanguageCodes.contains(
    ref.watch(localeControllerProvider).languageCode,
  );
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth is AuthAuthenticated) {
    // White-label: prefer the resolved Main-Agent (AGENT1) brand colours so a
    // store/POS renders in its agent's brand; fall back to the entity's own meta.
    final meta = auth.entity.meta;
    return buildBrandThemes(
      primaryHex: auth.brand.primaryColor.isNotEmpty ? auth.brand.primaryColor : meta.primaryColor,
      secondaryHex: auth.brand.secondaryColor.isNotEmpty ? auth.brand.secondaryColor : meta.secondaryColor,
      cursiveScript: cursive,
    );
  }
  return buildBrandThemes(cursiveScript: cursive);
});
