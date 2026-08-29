import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';

/// UX-135 / B-094 — **corner radii come from [IntesharRadii] or from a shape.**
///
/// B-094 moved the scale up (8→10, 12→14, 18→20) so every surface softened at
/// once. A site that kept a raw `8` or `12` therefore did not merely miss a
/// token: it kept the *pre-refresh* corner and sits visibly sharper than the
/// card next to it. Nothing in the app can notice that, because both sides are
/// just doubles.
///
/// The scan is deliberately narrow. It only looks at `BorderRadius.circular` and
/// `Radius.circular` — the two places a corner is stated as a number — and it
/// allows two shapes that are not steps on any scale:
///
/// * **half of a known box**, i.e. a circle (`circular(17)` on a 34×34 chip);
/// * **[IntesharRadii.pill]**, the "half my own height, whatever that is" end
///   cap. That idiom used to be a bare `999` at 25 sites, which is why every
///   previous audit of raw radii drowned in false positives and the real
///   stragglers stayed invisible;
/// * anything **below [IntesharRadii.xs]** — a 3px-tall progress track or a 3px
///   brand rule cannot take a 6px corner without becoming a lozenge, so the
///   scale's floor is where the scale stops applying, not where it starts being
///   ignored.
///
/// It asserts on the source rather than on a render because the defect is a
/// *relationship between files* — one screen's corner against the theme's — and
/// no single widget test can see both ends of it.
void main() {
  /// [src] with comment bodies blanked, preserving length. A radius quoted in a
  /// doc comment is prose, not a call site.
  String maskComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        if (i < 0) return line;
        // A `//` after an odd number of quotes is inside a string literal.
        final q1 = '\''.allMatches(line.substring(0, i)).length;
        final q2 = '"'.allMatches(line.substring(0, i)).length;
        if (q1.isOdd || q2.isOdd) return line;
        return line.substring(0, i);
      })
      .join('\n');

  final scale = <double>{
    IntesharRadii.xs,
    IntesharRadii.sm,
    IntesharRadii.md,
    IntesharRadii.lg,
    IntesharRadii.xl,
    IntesharRadii.pill,
  };

  /// Every `(file, line, value)` where a corner radius is written as a literal.
  List<(String, int, double)> literalRadii() {
    final out = <(String, int, double)>[];
    final pattern =
        RegExp(r'(?:BorderRadius|Radius)\.circular\(\s*(\d+(?:\.\d+)?)\s*\)');
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = maskComments(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in pattern.allMatches(lines[i])) {
          out.add((f.path, i + 1, double.parse(m.group(1)!)));
        }
      }
    }
    return out;
  }

  test('no surface is still on a pre-B-094 corner', () {
    // 8 and 12 are the values the refresh replaced. They are also the two most
    // reflexive numbers to type, which is exactly why they crept back.
    final stale = literalRadii()
        .where((r) => r.$3 == 8 || r.$3 == 12)
        .map((r) => '${r.$1}:${r.$2} → circular(${r.$3})')
        .toList();

    expect(stale, isEmpty,
        reason: 'B-094 raised these to ${IntesharRadii.sm} and '
            '${IntesharRadii.md}; a raw 8 or 12 renders the old, sharper '
            'corner beside refreshed surfaces');
  });

  test('the pill end cap is named, not a magic 999', () {
    final magic = literalRadii()
        .where((r) => r.$3 >= 100)
        .map((r) => '${r.$1}:${r.$2}')
        .toList();

    expect(magic, isEmpty,
        reason: 'use IntesharRadii.pill — a bare 999 reads as a mistake and '
            'buries the genuinely off-scale radii in any audit');
  });

  test('every literal radius is either on the scale or half of a circle', () {
    // A circle states its radius as half its own box (`circular(17)` inside a
    // 34×34 chip). That is not drift, and forcing it onto the scale would make
    // it an oval — so it is allowed, but nothing else is.
    final offenders = <String>[];
    for (final (path, line, value) in literalRadii()) {
      if (scale.contains(value)) continue;
      // Below the scale's floor: a progress track or a hairline rule.
      if (value < IntesharRadii.xs) continue;
      final src = File(path).readAsLinesSync();
      // The enclosing widget's own size, if it states one nearby.
      final window = src
          .sublist((line - 8).clamp(0, src.length), (line + 4).clamp(0, src.length))
          .join(' ');
      final sized = RegExp(r'(?:width|height|size):\s*(\d+(?:\.\d+)?)')
          .allMatches(window)
          .map((m) => double.parse(m.group(1)!));
      if (sized.any((s) => s == value * 2)) continue;
      offenders.add('$path:$line → circular($value)');
    }

    expect(offenders, isEmpty,
        reason: 'these are neither an IntesharRadii step nor half of the box '
            'they round, so they are drift');
  });
}
