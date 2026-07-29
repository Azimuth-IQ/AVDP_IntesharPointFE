import 'dart:math' as math;

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
///
/// B-094 follow-up: the POS tier was sage, which is ALSO the app's "credit /
/// money-in" colour (the `+` grants on this very page, the "after receiving"
/// figure in this very dialog). It is now ink, which additionally separates from
/// brand gold on luminance rather than hue — gold-vs-sage is the pair a
/// red-green-deficient operator cannot resolve.
void main() {
  EntitySummaryRow row(EntityType t) =>
      EntitySummaryRow(id: t.name, name: 'Target ${t.name}', type: t);

  /// WCAG relative luminance.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  /// WCAG contrast ratio. 3:1 is SC 1.4.11's bar for meaningful non-text colour,
  /// and it is the greyscale-safe bar: two hues that pass it stay apart for any
  /// colour-vision deficiency, because the separation is in lightness.
  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  Future<BuildContext> pumpTile(
    WidgetTester tester,
    EntityType type, {
    bool selected = false,
    Brightness brightness = Brightness.light,
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
    expect(pos, isNot(agent),
        reason: 'the two tiers must be distinguishable at a glance');
  });

  testWidgets('the POS tier does not borrow the money-in green', (tester) async {
    final ctx = await pumpTile(tester, EntityType.STORE);
    for (final c in [
      RecipientTile.tintFor(ctx, EntityType.STORE),
      RecipientTile.inkFor(ctx, EntityType.STORE),
    ]) {
      expect(c, isNot(IntesharColors.sage),
          reason: 'sage means "credit / money-in" everywhere else in the app — '
              'including the + rows and the "after receiving" figure this '
              'dialog shows alongside these tiles');
      expect(c, isNot(IntesharColors.sageOnDark));
      expect(c, isNot(Theme.of(ctx).colorScheme.secondary));
    }
  });

  testWidgets('the tiers separate on lightness, not hue alone', (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      final ctx = await pumpTile(tester, EntityType.STORE, brightness: b);
      for (final pair in [
        (
          RecipientTile.tintFor(ctx, EntityType.STORE),
          RecipientTile.tintFor(ctx, EntityType.AGENT2)
        ),
        (
          RecipientTile.inkFor(ctx, EntityType.STORE),
          RecipientTile.inkFor(ctx, EntityType.AGENT2)
        ),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(3.0),
            reason: 'a colour-blind operator resolves lightness, not hue: '
                '${pair.$1} vs ${pair.$2} in $b');
      }
    }
  });

  testWidgets('the tier glyph stays legible on its own badge', (tester) async {
    // Raw brand gold is a FILL, never a glyph — drawn at 16px on its own 12%
    // wash it lands at ~1.9:1 (B-078). `inkFor` is the corrected pair.
    for (final b in [Brightness.light, Brightness.dark]) {
      final ctx = await pumpTile(tester, EntityType.AGENT2, brightness: b);
      final surface = Theme.of(ctx).colorScheme.surface;
      for (final t in [EntityType.STORE, EntityType.AGENT2]) {
        final badge = Color.alphaBlend(
            RecipientTile.tintFor(ctx, t).withValues(alpha: 0.12), surface);
        expect(contrast(RecipientTile.inkFor(ctx, t), badge),
            greaterThanOrEqualTo(3.0),
            reason: 'tier glyph unreadable on its badge for ${t.name} in $b');
      }
    }
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

  testWidgets('the selection check is legible on the selected row',
      (tester) async {
    // The check is the ONLY non-colour cue for "this is the account being paid",
    // so it must not be drawn in the brand gold that also washes the row.
    for (final t in [EntityType.STORE, EntityType.AGENT2]) {
      final ctx = await pumpTile(tester, t, selected: true);
      final cs = Theme.of(ctx).colorScheme;
      final check = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      final wash =
          Color.alphaBlend(cs.primary.withValues(alpha: 0.12), cs.surface);
      expect(contrast(check.color!, wash), greaterThanOrEqualTo(4.5),
          reason: 'selection check washed out for ${t.name}');
    }
  });

  testWidgets('selection reads the same on both lists', (tester) async {
    // Selection is a STATE, not a tier: a per-tier wash tinted a picked POS row
    // light grey, i.e. "disabled" on the row the operator just chose.
    Color washOf(WidgetTester t) =>
        t.widget<ListTile>(find.byType(ListTile)).selectedTileColor!;

    await pumpTile(tester, EntityType.STORE, selected: true);
    final pos = washOf(tester);
    await pumpTile(tester, EntityType.AGENT2, selected: true);
    expect(pos, washOf(tester));
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
