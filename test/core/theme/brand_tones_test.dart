import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';

/// B-085: every brand-tinted colour must be DERIVED from the session's brand so a
/// white-label agent re-tints the whole UI. These pin the derivation contract —
/// the previous bug was widgets reading the hardcoded gold constants instead.
void main() {
  BrandTones tonesOf(ThemeData t) => t.extension<BrandTones>()!;

  group('default (no white-label override)', () {
    test('keeps the stock Sunburst gold', () {
      final tones = tonesOf(buildBrandThemes().light);
      expect(tones.brand, IntesharColors.saffron);
      expect(tones.brandInk, IntesharColors.saffronDeep);
      expect(tones.onBrand, IntesharColors.ink, reason: 'ink is legible on gold');
    });

    test('CTA is a FLAT brand fill, not a glossy gradient (B-094)', () {
      final tones = tonesOf(buildBrandThemes().light);
      final g = tones.ctaGradient;
      expect(g.length, 3);
      // The top two stops ARE the brand — no faux-gloss highlight.
      expect(g[0], IntesharColors.saffron);
      expect(g[1], IntesharColors.saffron);
      // Only a whisper of darkening at the very bottom, so it isn't a flat slab.
      expect(g[2].computeLuminance(), lessThan(g[1].computeLuminance()));
      // The chrome inner-highlight hairline is retired.
      expect(tones.ctaHighlight.a, 0, reason: 'no inner highlight — that pill was the dated tell');
    });
  });

  group('white-label override', () {
    test('a blue brand re-tints brand + CTA + wash (nothing stays gold)', () {
      const blue = Color(0xFF1565C0);
      final theme = buildBrandThemes(primaryHex: '#1565C0').light;
      final tones = tonesOf(theme);

      expect(tones.brand, blue);
      expect(theme.colorScheme.primary, blue);
      expect(tones.ctaGradient[1], blue, reason: 'the Sell pill body follows the brand');

      // Nothing may fall back to the stock gold.
      expect(tones.brand, isNot(IntesharColors.saffron));
      expect(tones.brandInk, isNot(IntesharColors.saffronDeep));
      expect(tones.brandWash, isNot(IntesharColors.dust));
      expect(theme.colorScheme.primaryContainer, isNot(IntesharColors.dust));
      expect(theme.colorScheme.onPrimaryContainer, isNot(IntesharColors.saffronDeep));
    });

    test('label ink flips to white on a dark brand', () {
      final dark = tonesOf(buildBrandThemes(primaryHex: '#0D47A1').light);
      expect(dark.onBrand, Colors.white);

      final light = tonesOf(buildBrandThemes(primaryHex: '#FFEB3B').light);
      expect(light.onBrand, IntesharColors.ink);
    });

    test('a pale brand is darkened for text so it stays legible on paper', () {
      const pale = Color(0xFFFFF59D); // very light yellow
      final tones = tonesOf(buildBrandThemes(primaryHex: '#FFF59D').light);
      expect(
        tones.brandInk.computeLuminance(),
        lessThan(pale.computeLuminance()),
        reason: 'brandInk must be darker than a pale brand (contrast on surface)',
      );
    });

    test('the CTA shadow is tinted by the brand, not the stock amber', () {
      final tones = tonesOf(buildBrandThemes(primaryHex: '#1565C0').light);
      expect(tones.ctaShadow, isNotEmpty);
      expect(tones.ctaShadow.first.color, isNot(IntesharShadows.ctaShadow.first.color));
    });
  });

  test('lerp interpolates without throwing (theme animation)', () {
    final a = tonesOf(buildBrandThemes().light);
    final b = tonesOf(buildBrandThemes(primaryHex: '#1565C0').light);
    final mid = a.lerp(b, 0.5);
    expect(mid.ctaGradient.length, a.ctaGradient.length);
    expect(mid.brand, isNot(a.brand));
  });
}
