import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';

/// UX-153 — the high-contrast theme.
///
/// The POS is a handheld used at a shop counter, frequently in daylight, and
/// the dark theme stays pinned off (see the note in `app.dart`). High contrast
/// is the accessibility answer that actually ships, so its VALUE is the ratios —
/// a "high contrast" mode that does not measure higher is worse than none,
/// because it looks like the need has been met.
///
/// These assert the theme is genuinely stronger than the default on every pair
/// a reader depends on, not merely different from it.
void main() {
  final normal = intesharLightTheme.colorScheme;
  final hc = intesharHighContrastTheme.colorScheme;

  /// Text pairs a reader must be able to resolve.
  final pairs = <String, (Color Function(ColorScheme), Color Function(ColorScheme))>{
    'body on page': ((s) => s.onSurface, (s) => s.surface),
    'body on card': ((s) => s.onSurface, (s) => s.surfaceContainerLowest),
    'secondary on page': ((s) => s.onSurfaceVariant, (s) => s.surface),
    'secondary on card': ((s) => s.onSurfaceVariant, (s) => s.surfaceContainerLowest),
    'on-primary on primary': ((s) => s.onPrimary, (s) => s.primary),
    'on-error on error': ((s) => s.onError, (s) => s.error),
  };

  group('every text pair clears WCAG AA', () {
    pairs.forEach((name, get) {
      test('$name — high contrast is at least 4.5:1', () {
        final r = contrastRatio(get.$1(hc), get.$2(hc));
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '$name measured ${r.toStringAsFixed(2)}:1 in high contrast');
      });
    });
  });

  group('it is actually higher than the default', () {
    pairs.forEach((name, get) {
      test('$name — no worse than the normal theme', () {
        // Not "different": HIGHER. A mode that trades one pair down to lift
        // another has not helped the person who turned it on.
        final n = contrastRatio(get.$1(normal), get.$2(normal));
        final h = contrastRatio(get.$1(hc), get.$2(hc));
        expect(h, greaterThanOrEqualTo(n - 0.001),
            reason: '$name dropped from ${n.toStringAsFixed(2)}:1 to '
                '${h.toStringAsFixed(2)}:1 when high contrast was turned ON');
      });
    });

    test('at least one pair is meaningfully stronger', () {
      // Guards against the flag being wired up but doing nothing at all.
      final improved = pairs.values.where((get) {
        final n = contrastRatio(get.$1(normal), get.$2(normal));
        final h = contrastRatio(get.$1(hc), get.$2(hc));
        return h > n + 0.5;
      }).length;
      expect(improved, greaterThan(0),
          reason: 'high contrast measured identical to the default everywhere — '
              'the switch would be doing nothing');
    });
  });

  test('secondary text reaches AAA, which is the mode\'s reason to exist', () {
    // Secondary text is the first thing lost in sunlight, and the builder raises
    // its floor from 4.5 to 7.0 in this mode.
    final r = contrastRatio(hc.onSurfaceVariant, hc.surface);
    expect(r, greaterThanOrEqualTo(7.0),
        reason: 'measured ${r.toStringAsFixed(2)}:1');
  });

  test('borders are visible without relying on a drop shadow', () {
    // The theme drops shadows in this mode (they read as mud at high contrast)
    // and separates surfaces with an outline instead — so the outline has to be
    // strong enough to BE the edge.
    final r = contrastRatio(hc.outline, hc.surface);
    expect(r, greaterThan(contrastRatio(normal.outline, normal.surface)),
        reason: 'the outline is the only surface separator left in this mode');
  });
}
