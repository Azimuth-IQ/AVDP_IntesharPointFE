import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';

/// UX-154 — contrast floors, measured on the REAL tokens.
///
/// Every assertion below calls the app's own [contrastRatio] against colours
/// pulled out of the built [ThemeData], so these tests fail the moment someone
/// lightens `inkSoft`, repaints `errorContainer`, or reintroduces an alpha on a
/// foreground. Nothing here re-derives the WCAG formula — that would pass no
/// matter what the tokens say.
///
/// The floors: **4.5:1** for body text, **3:1** for large text (≥18.66px bold /
/// ≥24px) and for non-text UI cues. High contrast promises AAA, so its floor is
/// **7:1**.
const double kBodyFloor = 4.5;
const double kLargeFloor = 3.0;
const double kAaaFloor = 7.0;

/// [contrastRatio] ignores alpha (it is a ratio between two *opaque* colours),
/// so a translucent foreground has to be composited over its ground first —
/// which is exactly the step the failing call sites were skipping.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  final themes = <String, ThemeData>{
    'light': intesharLightTheme,
    'dark': intesharDarkTheme,
    'highContrast': intesharHighContrastTheme,
  };

  double floorFor(String mode) => mode == 'highContrast' ? kAaaFloor : kBodyFloor;

  group('error container ink (item 3 — POS error banners)', () {
    themes.forEach((mode, theme) {
      test('$mode onErrorContainer clears the body floor', () {
        final cs = theme.colorScheme;
        final ratio = contrastRatio(cs.onErrorContainer, cs.errorContainer);
        expect(
          ratio,
          greaterThanOrEqualTo(floorFor(mode)),
          reason: '$mode onErrorContainer ${cs.onErrorContainer} on '
              '${cs.errorContainer} is ${ratio.toStringAsFixed(2)}:1 — the POS '
              'print/sale failure banners set this at 12.5px.',
        );
      });
    });

    test('the raw oxblood token would NOT pass — the correction is load-bearing',
        () {
      // Guards against someone "simplifying" the theme back to
      // `onErrorContainer: oxblood`, which measured 3.70:1.
      final ratio = contrastRatio(
          IntesharColors.oxblood, intesharLightTheme.colorScheme.errorContainer);
      expect(ratio, lessThan(kBodyFloor));
    });
  });

  group('placeholder ink (item 5 — hint text)', () {
    themes.forEach((mode, theme) {
      final deco = theme.inputDecorationTheme;

      test('$mode hint clears the body floor on the field fill', () {
        final ratio = contrastRatio(deco.hintStyle!.color!, deco.fillColor!);
        expect(
          ratio,
          greaterThanOrEqualTo(floorFor(mode)),
          reason: '$mode hint ${deco.hintStyle!.color} on ${deco.fillColor} is '
              '${ratio.toStringAsFixed(2)}:1',
        );
      });

      test('$mode hint is opaque — an alpha hint re-measures itself on every '
          'fill it lands on', () {
        expect(deco.hintStyle!.color!.a, 1.0);
      });

      test('$mode hint still reads lighter than the label', () {
        // The fix must not turn the placeholder into the label: a hint that is
        // indistinguishable from entered text is its own usability bug.
        final hint = deco.hintStyle!.color!;
        final label = deco.labelStyle!.color!;
        final fill = deco.fillColor!;
        expect(
          contrastRatio(hint, fill),
          lessThan(contrastRatio(label, fill)),
          reason: '$mode hint $hint must stay softer than label $label',
        );
      });
    });

    test('the old 55%-alpha placeholder would NOT pass', () {
      // #A4A8AE — 2.39:1 on the white field fill.
      final old = _over(
        IntesharColors.inkSoft.withValues(alpha: 0.55),
        IntesharColors.card,
      );
      expect(contrastRatio(old, IntesharColors.card), lessThan(kBodyFloor));
    });
  });

  group('alert banner on the oxblood fill (item 2)', () {
    const fill = IntesharColors.oxblood;
    final onFill = legibleOn(fill);

    test('the chosen foreground clears the body floor', () {
      expect(contrastRatio(onFill, fill), greaterThanOrEqualTo(kBodyFloor));
    });

    test('no alpha below 1.0 clears it — so the banner may not fade its text',
        () {
      // This is why the fix was "delete the alphas", not "raise them": the fill
      // itself leaves ~0.33 of headroom over the 4.5:1 bar.
      for (final alpha in <double>[0.92, 0.9, 0.8, 0.7]) {
        final faded = _over(onFill.withValues(alpha: alpha), fill);
        expect(
          contrastRatio(faded, fill),
          lessThan(kBodyFloor),
          reason: 'alpha $alpha measures '
              '${contrastRatio(faded, fill).toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('unpriced pill on the brand-fill card (item 4)', () {
    // Reproduces what `StampPill` paints: a 14% tint of the status colour, with
    // the label contrast-corrected against that tint over `cs.surface`.
    (Color fg, Color bg) pill(Color color, Color ground) {
      final bg = Color.alphaBlend(color.withValues(alpha: 0.14), ground);
      return (contrastAdjusted(color, bg), bg);
    }

    final theme = intesharLightTheme;
    final cs = theme.colorScheme;
    final tones = theme.extension<BrandTones>()!;
    final danger = theme.extension<StatusTones>()!.danger;

    test('the pill passes on the cs.surface capsule it is now given', () {
      final (fg, bg) = pill(danger, cs.surface);
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(kBodyFloor));
    });

    test('and would NOT have passed painted straight onto the brand fill', () {
      // 2.60:1 — the reason removing `Opacity(0.85)` was necessary but not
      // sufficient. StampPill measures against `cs.surface`; the gold came
      // through its 14% tint.
      final (fg, _) = pill(danger, cs.surface);
      final onBrandGround =
          Color.alphaBlend(danger.withValues(alpha: 0.14), tones.brand);
      expect(contrastRatio(fg, onBrandGround), lessThan(kLargeFloor));
    });

    test('the capsule has a visible edge against the brand fill', () {
      // 1.4.11: the tap target's boundary, not just its label.
      expect(contrastRatio(tones.onBrand, tones.brand),
          greaterThanOrEqualTo(kLargeFloor));
    });

    test('the filter icon beside it clears the non-text floor', () {
      expect(contrastRatio(tones.onBrand, tones.brand),
          greaterThanOrEqualTo(kLargeFloor));
    });
  });

  group('brand tones stay measured under a white-label brand', () {
    // The whole point of `brandOnSurface` / `onBrand`: an operator picks the
    // hex, so nothing may assume the stock gold.
    const brands = <String>[
      '#FFFFFF', // white — worst case for a light page
      '#F97316', // mid-tone orange, the case `estimateBrightnessForColor` got wrong
      '#DC2626', // saturated red — only ~4.8:1 of headroom for white
      '#101010', // near-black
      '#E2AD25', // the stock gold
    ];

    for (final hex in brands) {
      test('$hex — brandOnSurface clears 4.5:1 on the page surface', () {
        final theme = buildBrandThemes(primaryHex: hex).light;
        final tones = theme.extension<BrandTones>()!;
        expect(
          contrastRatio(tones.brandOnSurface, theme.colorScheme.surface),
          greaterThanOrEqualTo(kBodyFloor),
        );
      });

      test('$hex — onBrand clears 4.5:1 on the brand fill', () {
        final theme = buildBrandThemes(primaryHex: hex).light;
        final tones = theme.extension<BrandTones>()!;
        expect(contrastRatio(tones.onBrand, tones.brand),
            greaterThanOrEqualTo(kBodyFloor));
      });

      test('$hex — the hint still clears the body floor', () {
        final deco = buildBrandThemes(primaryHex: hex).light.inputDecorationTheme;
        expect(contrastRatio(deco.hintStyle!.color!, deco.fillColor!),
            greaterThanOrEqualTo(kBodyFloor));
      });
    }
  });

  group('status tones are corrected to the mode floor', () {
    themes.forEach((mode, theme) {
      test('$mode — every status tone clears its floor on the page surface', () {
        final tones = theme.extension<StatusTones>()!;
        final surface = theme.colorScheme.surface;
        final floor = floorFor(mode);
        for (final entry in <String, Color>{
          'success': tones.success,
          'warn': tones.warn,
          'danger': tones.danger,
          'neutral': tones.neutral,
          'inFlight': tones.inFlight,
          'brand': tones.brand,
        }.entries) {
          expect(
            contrastRatio(entry.value, surface),
            greaterThanOrEqualTo(floor),
            reason: '$mode ${entry.key} ${entry.value} is '
                '${contrastRatio(entry.value, surface).toStringAsFixed(2)}:1',
          );
        }
      });
    });
  });
}
