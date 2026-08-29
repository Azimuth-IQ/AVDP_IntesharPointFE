import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/inventory/presentation/inventory_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// The SKU row's leading treatment.
///
/// The row used to open with a 44×44 brand-gold circle holding the SKU. A circle
/// is an avatar treatment, and a SKU is a part number: the live catalog carries
/// `ASIACELL-5000`, thirteen monospace characters at 12px with 0.6 tracking —
/// roughly 100px of text asked to fit inside 44px. It wrapped and clipped.
///
/// These render the REAL widget with the REAL fonts. The default test font draws
/// every glyph as a square of the font size, so any assertion about text fitting
/// is fiction without this — see the same `setUpAll` in `pos_step_header_test`.
void main() {
  setUpAll(() async {
    final codec = FontLoader('CodecPro');
    for (final f in [
      'CodecPro-Heavy.ttf',
      'CodecPro-ExtraBold.ttf',
      'CodecPro-Bold.ttf',
      'CodecPro-Regular.ttf',
      'CodecPro-News.ttf',
    ]) {
      codec.addFont(Future.value(
          ByteData.sublistView(await File('assets/fonts/$f').readAsBytes())));
    }
    await codec.load();

    final mono = FontLoader('JetBrainsMono');
    for (final f in [
      'JetBrainsMono-Regular.ttf',
      'JetBrainsMono-Medium.ttf',
      'JetBrainsMono-SemiBold.ttf',
      'JetBrainsMono-Bold.ttf',
    ]) {
      mono.addFont(Future.value(ByteData.sublistView(
          await File('assets/fonts/mono/$f').readAsBytes())));
    }
    await mono.load();
  });

  SkuSummary summary(String sku, String name) => SkuSummary(
        sku: sku,
        name: name,
        defaultPrice: 5000,
        total: 240,
        available: 212,
        printed: 26,
        damaged: 2,
      );

  Future<void> pump(WidgetTester tester, SkuSummary s,
      {double width = 900}) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildBrandThemes().light,
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SkuGroupCard(
              summary: s,
              entityId: 'e1',
              readOnly: true,
              lowStock: 50,
              onChanged: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the real catalog SKU renders in full, on one line', (t) async {
    await pump(t, summary('ASIACELL-5000', 'ASIACELL_5000'));

    // The whole code, not an ellipsized head of it: the SKU is what an operator
    // reads back to identify the product.
    final sku = find.text('ASIACELL-5000');
    expect(sku, findsOneWidget);

    final box = t.renderObject<RenderBox>(sku);
    final style = t.widget<Text>(sku).style!;
    expect(box.size.height, lessThan(style.fontSize! * 2),
        reason: 'more than one line high means it wrapped, which is the bug '
            'the 44px circle had');
    expect(t.takeException(), isNull);
  });

  testWidgets('a long SKU degrades by ellipsis, not by overflowing', (t) async {
    // Nothing constrains SKU length at the catalog end, so the row has to cope.
    await pump(t, summary('ASIACELL-PREPAID-VOUCHER-25000-IQ', 'Asiacell 25k'),
        width: 420);
    expect(t.takeException(), isNull,
        reason: 'a render overflow throws in a widget test');
  });

  testWidgets('the SKU is set in the mono family, not the display face',
      (t) async {
    // It is a code. Proportional digits make two serials of equal length look
    // unequal, which is why kMonoFamily exists.
    await pump(t, summary('ASIACELL-5000', 'ASIACELL_5000'));
    expect(t.widget<Text>(find.text('ASIACELL-5000')).style!.fontFamily,
        kMonoFamily);
  });

  testWidgets('renders a picture of the row for review', (t) async {
    await pump(t, summary('ASIACELL-5000', 'ASIACELL_5000'));
    await expectLater(find.byType(SkuGroupCard),
        matchesGoldenFile('goldens/sku_row.png'));
  }, skip: !Platform.environment.containsKey('RENDER_GOLDENS'));
}
