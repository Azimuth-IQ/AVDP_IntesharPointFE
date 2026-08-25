import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/shared/widgets/brand_band.dart';

/// B-083: white-label helpers for the POS session. The POS follows the owning
/// Main-Agent's brand (logo + colours) and the shop's own name — never the
/// Inteshar star/wordmark. Colours already flow through the theme; these render
/// the agent LOGO (with a neutral shop-initial fallback) and the shop NAME.

/// The signed-in shop's own trade name (empty when unavailable).
String posShopName(WidgetRef ref) {
  final auth = ref.read(authStateProvider).valueOrNull;
  return auth is AuthAuthenticated ? auth.entity.meta.name.trim() : '';
}

/// The owning agent's white-label logo URL (empty when unset).
String posAgentLogo(WidgetRef ref) {
  final auth = ref.read(authStateProvider).valueOrNull;
  return auth is AuthAuthenticated ? auth.brand.agentLogoUrl.trim() : '';
}

/// A white-label mark: the agent's logo when set, otherwise the shop's initial
/// in a tinted disc (or a neutral storefront icon). Replaces the Inteshar star
/// everywhere in the POS surface.
class PosBrandMark extends ConsumerWidget {
  const PosBrandMark({super.key, this.size = 40, this.tint});

  final double size;

  /// Colour for the fallback initial/icon; defaults to `onSurface`.
  final Color? tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final color = tint ?? cs.onSurface;
    final logo = posAgentLogo(ref);
    if (logo.isNotEmpty) {
      return Image.network(
        logo,
        height: size,
        fit: BoxFit.contain,
        // UX-150: the brand mark stands in for the shop's own name in the app
        // bar and on the voucher — without a description it is announced as an
        // unlabelled image.
        semanticLabel: posShopName(ref),
        errorBuilder: (_, _, _) => _fallback(ref, color),
      );
    }
    return _fallback(ref, color);
  }

  Widget _fallback(WidgetRef ref, Color color) {
    final name = posShopName(ref);
    if (name.isEmpty) {
      return Icon(Icons.storefront_outlined, size: size, color: color);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Text(
        name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontFamily: 'CodecPro',
          fontSize: size * 0.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

/// The full-bleed brand hero shown on the POS PIN lock/setup screens. Renders on
/// the agent's primary colour (via the theme) with the agent logo + shop name —
/// no Inteshar star or "Inteshar Platform" wordmark.
class PosBrandHero extends ConsumerWidget {
  const PosBrandHero({super.key, required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final onBrand = cs.onPrimary; // legible on any brand colour
    final logo = posAgentLogo(ref);
    final name = posShopName(ref);
    final headline = name.isNotEmpty ? name : (ar ? 'نقطة البيع' : 'Point of Sale');

    return BrandBand(
      background: cs.primary,
      sparkle: false, // no decorative Inteshar star on a white-labelled surface
      padding: wide
          ? const EdgeInsets.fromLTRB(56, 56, 56, 56)
          : const EdgeInsets.fromLTRB(28, 28, 28, 28),
      child: Column(
        mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The agent logo sits in a white chip so it stays legible on the brand
          // colour; with no logo we show a neutral POS glyph in the on-brand ink.
          if (logo.isNotEmpty)
            Container(
              padding: EdgeInsets.all(wide ? 14 : 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(IntesharRadii.md),
              ),
              child: Image.network(
                logo,
                height: wide ? 64 : 40,
                fit: BoxFit.contain,
                semanticLabel: name.isNotEmpty ? name : headline,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.point_of_sale, size: wide ? 64 : 40, color: cs.primary),
              ),
            )
          else
            Icon(Icons.point_of_sale, size: wide ? 64 : 40, color: onBrand),
          SizedBox(height: wide ? 28 : 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              headline,
              style: TextStyle(
                fontFamily: 'CodecPro',
                color: onBrand,
                fontSize: wide ? 52 : 32,
                fontWeight: FontWeight.w900,
                letterSpacing: wide ? -2.0 : -1.0,
                height: 1.0,
              ),
            ),
          ),
          if (name.isNotEmpty) ...[
            SizedBox(height: wide ? 20 : 6),
            Text(
              ar ? 'نقطة البيع' : 'Point of Sale',
              style: TextStyle(
                fontFamily: 'CodecPro',
                color: onBrand.withValues(alpha: 0.78),
                fontSize: wide ? 17 : 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
