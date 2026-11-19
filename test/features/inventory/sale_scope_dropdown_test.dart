import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/geo/governorate_picker.dart';

/// PROD-015: the client asked for the sale scope to be one selector — "all governorates" first,
/// Baghdad second, then the rest — and for pasting to come before the file button.
void main() {
  Future<List<(bool, String?)>> pump(WidgetTester tester, {bool? locked, String? gov}) async {
    final calls = <(bool, String?)>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: SaleScopeDropdown(
          regionLocked: locked,
          governorate: gov,
          onChanged: (l, g) => calls.add((l, g)),
        ),
      ),
    ));
    return calls;
  }

  testWidgets('nothing is chosen until the operator chooses', (tester) async {
    await pump(tester);
    expect(find.text('— اختر نطاق البيع —'), findsOneWidget);
  });

  testWidgets('the order is: all governorates, Baghdad, then the others', (tester) async {
    await pump(tester);
    await tester.tap(find.text('— اختر نطاق البيع —'));
    await tester.pumpAndSettle();
    final all = tester.getTopLeft(find.text('كل المحافظات').last).dy;
    final baghdad = tester.getTopLeft(find.text('بغداد').last).dy;
    final basra = tester.getTopLeft(find.text('البصرة').last).dy;
    expect(all, lessThan(baghdad));
    expect(baghdad, lessThan(basra));
  });

  testWidgets('choosing "all" answers region-free; choosing Baghdad locks to Baghdad', (tester) async {
    final calls = await pump(tester);
    await tester.tap(find.text('— اختر نطاق البيع —'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل المحافظات').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل المحافظات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بغداد').last);
    await tester.pumpAndSettle();
    expect(calls, [(false, null), (true, 'BAGHDAD')]);
  });

  test('an answered scope shows its answer', () {
    expect(SaleScopeDropdown.valueFor(null, null), isNull);
    expect(SaleScopeDropdown.valueFor(false, null), SaleScopeDropdown.all);
    expect(SaleScopeDropdown.valueFor(true, 'BASRA'), 'BASRA');
  });

  test('the upload page uses the dropdown, and the paste box comes before the file button', () {
    final src = File('lib/features/inventory/presentation/batch_add_page.dart').readAsStringSync();
    expect(src, contains('SaleScopeDropdown('));
    expect(src, isNot(contains("'محافظة محددة'")));
    final paste = src.indexOf("SectionLabel(_tr(context, 'الصق الصفوف'");
    final file = src.indexOf('onPressed: _pickFile');
    expect(paste, isNonNegative);
    expect(paste, lessThan(file));
  });
}
