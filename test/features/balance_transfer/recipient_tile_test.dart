import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/balance_transfer/presentation/recipient_tile.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// B-109: a POS point and a sub-agent are different KINDS of recipient — money
/// sent to a counter is spent there, not passed further down — but the rows
/// differed only by a small grey icon and read as one flat list.
void main() {
  EntitySummaryRow row(EntityType t) =>
      EntitySummaryRow(id: t.name, name: 'Target ${t.name}', type: t);

  Future<BuildContext> pumpTile(
    WidgetTester tester,
    EntityType type, {
    bool selected = false,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: buildBrandThemes().light,
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return RecipientTile(row: row(type), selected: selected, onTap: () {});
        }),
      ),
    ));
    await tester.pump();
    return ctx;
  }

  testWidgets('a POS point and an agent never share a tint', (tester) async {
    final ctx = await pumpTile(tester, EntityType.STORE);
    final pos = RecipientTile.tintFor(ctx, EntityType.STORE);
    final agent = RecipientTile.tintFor(ctx, EntityType.AGENT2);
    expect(pos, isNot(agent), reason: 'the two tiers must be distinguishable at a glance');
    expect(pos, IntesharColors.sage);
  });

  testWidgets('each tier states what it is, not just its name', (tester) async {
    for (final t in [EntityType.STORE, EntityType.AGENT2, EntityType.AGENT1]) {
      await pumpTile(tester, t);
      expect(find.text('Target ${t.name}'), findsOneWidget);
      final l = AppLocalizations.of(tester.element(find.byType(RecipientTile)))!;
      final label = RecipientTile.tierLabel(l, t);
      expect(find.text(label), findsOneWidget,
          reason: 'the tier must be named on the row for ${t.name}');
      // The screen is Arabic; an English enum label would be a regression.
      expect(RegExp(r'[؀-ۿ]').hasMatch(label), isTrue,
          reason: 'tier label must be localized, got "\$label"');
    }
  });

  testWidgets('a POS row is marked with a storefront, an agent with a building',
      (tester) async {
    await pumpTile(tester, EntityType.STORE);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(find.byIcon(Icons.apartment_outlined), findsNothing);

    await pumpTile(tester, EntityType.AGENT2);
    expect(find.byIcon(Icons.apartment_outlined), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsNothing);
  });

  testWidgets('selection is shown by a check, not colour alone', (tester) async {
    await pumpTile(tester, EntityType.STORE, selected: false);
    expect(find.byIcon(Icons.check_circle), findsNothing);

    await pumpTile(tester, EntityType.STORE, selected: true);
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: 'a tint change alone is invisible to a colour-blind operator');
  });

  testWidgets('tapping reports the choice', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildBrandThemes().light,
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RecipientTile(
          row: row(EntityType.STORE),
          selected: false,
          onTap: () => tapped = true,
        ),
      ),
    ));
    await tester.tap(find.byType(RecipientTile));
    expect(tapped, isTrue);
  });
}
