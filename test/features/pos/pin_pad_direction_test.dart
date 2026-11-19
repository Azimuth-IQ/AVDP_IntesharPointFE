import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pos/presentation/pos_pin_lock_page.dart';

/// PROD-009: the client's photo showed the PIN pad reading 3 2 1 in Arabic. A number pad reads
/// 1 2 3 left to right in every language, like a phone or a card terminal.
void main() {
  Future<void> pumpPad(WidgetTester tester, TextDirection dir, {List<String>? typed}) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Scaffold(
          body: SizedBox(
            width: 360,
            child: PosPinPad(
              enabled: true,
              onDigit: (d) => typed?.add(d),
              onBackspace: () {},
              onToggleObscure: () {},
              obscure: true,
              cs: ThemeData.light().colorScheme,
            ),
          ),
        ),
      ),
    ));
  }

  double x(WidgetTester tester, String digit) => tester.getCenter(find.text(digit)).dx;

  for (final dir in TextDirection.values) {
    testWidgets('reads 1 2 3 left to right (${dir.name})', (tester) async {
      await pumpPad(tester, dir);
      expect(x(tester, '1'), lessThan(x(tester, '2')));
      expect(x(tester, '2'), lessThan(x(tester, '3')));
      expect(x(tester, '7'), lessThan(x(tester, '9')));
      // Bottom row: show/hide on the left, backspace on the right, 0 in the middle.
      expect(tester.getCenter(find.byIcon(Icons.visibility_outlined)).dx, lessThan(x(tester, '0')));
      expect(x(tester, '0'), lessThan(tester.getCenter(find.byIcon(Icons.backspace_outlined)).dx));
    });
  }

  testWidgets('in Arabic, tapping the top-left key types 1', (tester) async {
    final typed = <String>[];
    await pumpPad(tester, TextDirection.rtl, typed: typed);
    final keys = find.byType(InkWell);
    // The first key laid out is the top-left one in a left-to-right pad.
    final topLeft = tester.getTopLeft(find.text('1'));
    expect(topLeft.dx, lessThan(180), reason: '1 must sit on the left half of a 360-wide pad');
    await tester.tap(find.text('1'));
    expect(typed, ['1']);
    expect(keys, findsNWidgets(12));
  });
}
