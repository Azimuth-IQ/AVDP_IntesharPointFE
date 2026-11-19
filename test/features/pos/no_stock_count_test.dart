import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PROD-013: the client does not want shops to see how many cards are available — the number is the
/// main agent's stock. The POS sell screens used to print it in three places ("يمكن بيع N" on the
/// tile, "المتوفر في مخزن الوكيل: N" on the sheet, "الحد الأقصى N" by the quantity).
///
/// The screens are private widgets deep in pos_home_page.dart, so this guards the source: no
/// user-visible string may interpolate a stock-derived number. The shop's OWN limits may still be
/// stated (its daily cap, what its balance covers) — those are the two allowed lines.
void main() {
  final source = File('lib/features/pos/presentation/pos_home_page.dart').readAsLinesSync();

  // A string literal that interpolates a stock-derived value.
  final stockNumber = RegExp(r"""['"][^'"]*\$\{?[\w.]*(available|affordable|_maxQty)[\w.]*\}?[^'"]*['"]""");
  const allowed = ['الحد اليومي', 'Daily limit', 'رصيدك يكفي \$_maxQty', 'Your balance covers \$_maxQty'];

  test('no POS string prints a stock count', () {
    final offenders = <String>[];
    for (var i = 0; i < source.length; i++) {
      final line = source[i];
      if (line.trimLeft().startsWith('//')) continue;
      if (!stockNumber.hasMatch(line)) continue;
      if (allowed.any(line.contains)) continue;
      offenders.add('${i + 1}: ${line.trim()}');
    }
    expect(offenders, isEmpty, reason: 'stock counts shown to shops:\n${offenders.join('\n')}');
  });

  test('the removed wordings are gone', () {
    final text = source.join('\n');
    expect(text, isNot(contains('المتوفر في مخزن الوكيل')));
    expect(text, isNot(contains('يمكن بيع \$')));
    expect(text, isNot(contains("'الحد الأقصى \$_maxQty'")));
  });
}
