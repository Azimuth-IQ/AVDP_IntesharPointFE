import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';

/// The contrast maths behind white-label theming.
///
/// A Main Agent picks their own brand colour and it is applied across their
/// whole subtree, so an unreadable pick makes every button label in a
/// governorate illegible. These assert against WCAG's published reference
/// values rather than against our own implementation — the point is that the
/// numbers are *right*, not that they are stable.
void main() {
  const white = Color(0xFFFFFFFF);
  const black = Color(0xFF000000);

  group('contrastRatio', () {
    test('matches the WCAG reference extremes', () {
      // Black on white is the defined maximum, 21:1; a colour on itself is 1:1.
      expect(contrastRatio(black, white), closeTo(21.0, 0.01));
      expect(contrastRatio(white, white), closeTo(1.0, 0.001));
    });

    test('is symmetric — order of the pair cannot change the verdict', () {
      const brand = Color(0xFFE2AD25);
      expect(contrastRatio(brand, white), closeTo(contrastRatio(white, brand), 1e-9));
    });

    test('agrees with published values for known pairs', () {
      // #767676 on white is the canonical "exactly passes AA body text" grey.
      expect(contrastRatio(const Color(0xFF767676), white), closeTo(4.54, 0.02));
      // Material blue 500 on white, a widely cited 3.13:1 near-miss.
      expect(contrastRatio(const Color(0xFF2196F3), white), closeTo(3.13, 0.02));
    });
  });

  group('legibleOn', () {
    // The bug this replaced: Flutter's estimateBrightnessForColor flips at
    // luminance 0.337, so a MID-LIGHT brand was handed white when black scored
    // far better. Orange is the worst realistic case.
    test('picks black on a mid-light brand, where the old threshold picked white', () {
      const orange = Color(0xFFF97316);
      final fg = legibleOn(orange, light: white, dark: black);
      expect(fg, black);
      expect(contrastRatio(fg, orange), greaterThan(contrastRatio(white, orange)));
    });

    test('still picks white on a genuinely dark brand', () {
      const navy = Color(0xFF1D4ED8);
      expect(legibleOn(navy, light: white, dark: black), white);
    });

    test('always returns whichever candidate actually scores higher', () {
      for (final brand in const [
        Color(0xFFE2AD25), // stock saffron
        Color(0xFFED1C24), // Asiacell red
        Color(0xFF0F766E), // deep teal
        Color(0xFFFFF59D), // pale yellow
        Color(0xFF808080), // mid grey — the hardest case
      ]) {
        final fg = legibleOn(brand, light: white, dark: black);
        final other = fg == white ? black : white;
        expect(contrastRatio(fg, brand),
            greaterThanOrEqualTo(contrastRatio(other, brand)),
            reason: 'picked the worse foreground for $brand');
      }
    });
  });

  group('contrastAdjusted', () {
    test('lifts a failing colour to at least the requested ratio', () {
      // Raw brand gold as TEXT on paper is the case that started this: 2.05:1.
      const paper = Color(0xFFF6F7F9);
      const gold = Color(0xFFE2AD25);
      expect(contrastRatio(gold, paper), lessThan(4.5));

      final fixed = contrastAdjusted(gold, paper);
      expect(contrastRatio(fixed, paper), greaterThanOrEqualTo(4.5));
    });

    test('leaves a colour that already passes alone', () {
      const paper = Color(0xFFF6F7F9);
      const ink = Color(0xFF16181D);
      expect(contrastAdjusted(ink, paper), ink);
    });

    test('keeps the hue recognisable — it darkens, it does not go grey', () {
      const paper = Color(0xFFF6F7F9);
      const gold = Color(0xFFE2AD25);
      final fixed = HSLColor.fromColor(contrastAdjusted(gold, paper));
      final original = HSLColor.fromColor(gold);
      expect((fixed.hue - original.hue).abs(), lessThan(6.0));
      expect(fixed.saturation, greaterThan(0.25),
          reason: 'a washed-out result would stop reading as the brand');
    });

    test('terminates on the extremes instead of looping', () {
      // Nothing can make white pass against white; it must give up, not hang.
      expect(() => contrastAdjusted(white, white), returnsNormally);
      expect(() => contrastAdjusted(black, black), returnsNormally);
    });
  });
}
