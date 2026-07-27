import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/reports/presentation/reports_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// B-104: reports are tabular data. Rendered as a card per record, the content
/// pinned to one edge and 50–70% of every card was empty — so the report surface
/// is now a real table on wide screens and a two-line row on narrow ones.
///
/// The branch is a width threshold, which is exactly the kind of thing that
/// silently regresses. These pin both sides of it.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBrandThemes().light,
        locale: const Locale('ar'),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReportsPreviewPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Every Text on screen whose content mentions [needle].
  Iterable<String> textsContaining(String needle) => find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((d) => d.contains(needle));

  const owner = 'أحمد علي حسن';
  const phone = '07701234567';

  testWidgets('wide: owner and phone are their OWN cells in a table', (tester) async {
    await pump(tester, const Size(1200, 900));

    // Column headers exist — proof the table header rendered rather than cards.
    expect(find.text('المالك'), findsOneWidget);
    expect(find.text('الهاتف'), findsOneWidget);

    // Each value sits in its own cell, not concatenated into a subtitle.
    expect(textsContaining(owner).length, 1);
    expect(textsContaining(owner).first, owner);
    expect(textsContaining(phone).first, phone);
  });

  testWidgets('narrow: the same values collapse into ONE meta line', (tester) async {
    await pump(tester, const Size(360, 900));

    // No per-column header on a phone — that was the point of the two-line row.
    expect(find.text('المالك'), findsNothing);

    // Owner and phone now share a single muted line joined by '·'.
    final meta = textsContaining(owner).toList();
    expect(meta, isNotEmpty, reason: 'the owner must still be shown, just merged');
    expect(meta.first.contains(phone), isTrue,
        reason: 'narrow rows join the secondary values into one line: ${meta.first}');
    expect(meta.first.contains('·'), isTrue);
  });

  testWidgets('the row identity and its figure survive BOTH layouts', (tester) async {
    for (final size in [const Size(1200, 900), const Size(360, 900)]) {
      await pump(tester, size);
      expect(find.text('مكتب سعد للاتصالات'), findsOneWidget,
          reason: 'identity must never be dropped at ${size.width}px');
      expect(textsContaining('25,876,000'), isNotEmpty,
          reason: 'the balance must never be dropped at ${size.width}px');
    }
  });
}
