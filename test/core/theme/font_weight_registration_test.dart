import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';

/// UX-160. `pubspec.yaml` declared five of Codec Pro's six upright faces at the
/// wrong weight, and News — which sits BELOW Regular — was declared at 500. So
/// every `FontWeight.w500` rendered lighter than the `w400` body text it was
/// written to emphasise, and nothing failed.
///
/// This reads the real pubspec rather than restating the mapping, because the
/// bug was a disagreement between two files: the fix is only true while they
/// still agree.
void main() {
  /// Codec Pro's faces from lightest to darkest. Measured normalised ink area
  /// over 'HOnoeas', which agrees with each face's own OS/2.usWeightClass:
  ///   Light 0.0878 (200) · News 0.1130 (300) · Regular 0.1254 (400)
  ///   Bold 0.1666 (500) · ExtraBold 0.2016 (600) · Heavy 0.2295 (700)
  const faceOrder = <String>[
    'Light',
    'News',
    'Regular',
    'Bold',
    'ExtraBold',
    'Heavy',
  ];

  /// (face, declaredWeight) pairs for the CodecPro family, in pubspec order.
  List<(String, int)> readRegistration() {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final start = lines.indexWhere((l) => l.contains('family: CodecPro'));
    expect(start, isNot(-1), reason: 'CodecPro family not found in pubspec.yaml');

    final out = <(String, int)>[];
    String? pending;
    for (final line in lines.skip(start + 1)) {
      // Stop at the next family block.
      if (line.contains('family:')) break;
      final asset = RegExp(r'CodecPro-(\w+)\.ttf').firstMatch(line);
      if (asset != null) {
        pending = asset.group(1);
        continue;
      }
      final weight = RegExp(r'weight:\s*(\d+)').firstMatch(line);
      if (weight != null && pending != null) {
        out.add((pending, int.parse(weight.group(1)!)));
        pending = null;
      }
    }
    return out;
  }

  test('every registered face is one we know the darkness of', () {
    for (final (face, _) in readRegistration()) {
      expect(faceOrder, contains(face),
          reason: 'unknown face "$face" — measure it before registering it');
    }
  });

  test('declared weights ascend with actual face darkness', () {
    // THE regression. A face declared out of order means a higher FontWeight
    // renders lighter than a lower one, which is exactly what News at 500 did.
    final reg = readRegistration();
    final byDarkness = [...reg]
      ..sort((a, b) => faceOrder.indexOf(a.$1).compareTo(faceOrder.indexOf(b.$1)));

    for (var i = 1; i < byDarkness.length; i++) {
      final lighter = byDarkness[i - 1];
      final darker = byDarkness[i];
      expect(
        darker.$2,
        greaterThan(lighter.$2),
        reason: '${darker.$1} is darker than ${lighter.$1} but is declared at '
            'weight ${darker.$2} <= ${lighter.$2} — a higher FontWeight would '
            'render lighter',
      );
    }
  });

  test('News is declared below Regular', () {
    // Named on its own because this is the specific inversion that shipped.
    final reg = Map.fromEntries(readRegistration().map((e) => MapEntry(e.$1, e.$2)));
    expect(reg['News'], isNotNull);
    expect(reg['Regular'], isNotNull);
    expect(reg['News']! < reg['Regular']!, isTrue,
        reason: 'News is lighter than Regular and must be declared lighter');
  });

  test('the weight tokens point at weights that actually have a face', () {
    final declared = readRegistration().map((e) => e.$2).toSet();
    for (final w in IntesharWeight.registered) {
      expect(declared, contains(w.value),
          reason: 'IntesharWeight token w${w.value} has no face in pubspec.yaml');
    }
  });

  test('semibold stays an alias of bold while no 600 face exists', () {
    // There is nothing between Regular and Bold in this family. If a real
    // SemiBold is ever licensed, this test is the reminder to re-point it.
    final declared = readRegistration().map((e) => e.$2).toSet();
    expect(declared.contains(600), isFalse,
        reason: 'a 600 face now exists — point IntesharWeight.semibold at it');
    expect(IntesharWeight.semibold, IntesharWeight.bold);
  });

  test('a literal w500 can no longer resolve lighter than body', () {
    // w500 has no face. What matters after the fix is that the nearest
    // candidates are Regular and Bold — not News.
    final declared = readRegistration();
    final atOrBelow500 =
        declared.where((e) => e.$2 <= 500).map((e) => e.$2).toList()..sort();
    expect(atOrBelow500.last, IntesharWeight.regular.value,
        reason: 'the heaviest face at or below 500 must be Regular, so a w500 '
            'site falls back to body weight rather than something lighter');
  });
}
