import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/balance_transfer/presentation/transfers_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// B-094 demoted brand gold from a surface-carrier to a ≤10% accent — white
/// cards, a thin brand rule, `elev1` and a hairline border. Every hero card was
/// converted except this one, which shipped to the customer as a full gold slab
/// (their own screenshot of the transfers screen is what caught it).
void main() {
  Future<BuildContext> pumpCard(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    num amount = 25876000,
  }) async {
    late BuildContext ctx;
    final themes = buildBrandThemes();
    await tester.pumpWidget(MaterialApp(
      theme: brightness == Brightness.dark ? themes.dark : themes.light,
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return Center(
            child: SizedBox(
              width: 420,
              child: TransferBalanceCard(label: 'الرصيد المتاح', amount: amount),
            ),
          );
        }),
      ),
    ));
    await tester.pump();
    return ctx;
  }

  /// [0] is the card surface, [1] the brand rule.
  List<Container> boxes(WidgetTester tester) => tester
      .widgetList<Container>(find.descendant(
        of: find.byType(TransferBalanceCard),
        matching: find.byType(Container),
      ))
      .toList();

  testWidgets('the card is a card, not a gold slab', (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      final ctx = await pumpCard(tester, brightness: b);
      final cs = Theme.of(ctx).colorScheme;
      final deco = boxes(tester).first.decoration! as BoxDecoration;

      // UX-126: the fill is the app's ONE card fill. It used to be `cs.surface`
      // — the page background — so the card was a rectangle of border sitting
      // next to real InkCards.
      expect(deco.color, cs.surfaceContainer);
      expect(deco.color, isNot(cs.surface),
          reason: 'UX-126: a card is never the page colour');
      expect(deco.color, isNot(ctx.tones.brand),
          reason: 'B-094: brand gold no longer carries a whole surface');
      expect(deco.border, Border.all(color: cs.outlineVariant),
          reason: 'depth comes from the hairline, not from the fill');
      expect(deco.boxShadow, IntesharShadows.elev1);
      expect(deco.borderRadius, BorderRadius.circular(IntesharRadii.lg));
    }
  });

  testWidgets('brand gold survives only as a thin accent rule', (tester) async {
    final ctx = await pumpCard(tester);
    final rule = boxes(tester)[1];
    expect((rule.decoration! as BoxDecoration).color, ctx.tones.brand);

    final card = tester.getSize(find.byType(TransferBalanceCard));
    final accent = tester.getSize(find.byWidget(rule));
    final share = (accent.width * accent.height) / (card.width * card.height);
    expect(share, lessThan(0.10),
        reason: 'the brand accent must stay under a tenth of the card, '
            'got ${(share * 100).toStringAsFixed(1)}%');
  });

  testWidgets('the number is the hero, in ink on paper', (tester) async {
    final ctx = await pumpCard(tester, amount: 25876000);
    final cs = Theme.of(ctx).colorScheme;

    final amount = tester.widget<Text>(find.text(Formatters.iqd(25876000)));
    expect(amount.style!.color, cs.onSurface);
    expect(amount.style!.fontSize, 32);
    expect(amount.style!.fontWeight, FontWeight.w900);

    // The label is the muted overline, not ink-at-70%-on-gold.
    final label = tester.widget<Text>(find.text('الرصيد المتاح'));
    expect(label.style!.color, cs.onSurfaceVariant);
  });

  testWidgets('a rounded amount still renders', (tester) async {
    await pumpCard(tester, amount: 1234.6);
    expect(find.text(Formatters.iqd(1235)), findsOneWidget);
  });
}
