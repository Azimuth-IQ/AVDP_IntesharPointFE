import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// UX-135 — [CardDensity] against the paddings it replaced.
///
/// Thirty-odd `InkCard` sites used to spell their inset out by hand. Replacing
/// `padding: const EdgeInsets.all(16)` with a named density is only safe if the
/// two render *identically*, and the one thing that cannot prove that is reading
/// `CardDensity.normal.value` back — that restates the source and would still
/// pass if the card ignored the value entirely.
///
/// So every assertion below measures the **rendered gap** between the card's box
/// and its child's box, and compares a density against the literal padding it
/// was migrated from. Both sides go through the real `InkCard.build`.
void main() {
  const childKey = Key('card-child');

  Future<Widget> pump(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildBrandThemes().light,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 300, child: card),
        ),
      ),
    ));
    return card;
  }

  /// The four rendered insets (start/top/end/bottom) between [InkCard]'s own box
  /// and its child's box, in logical pixels.
  ({double left, double top, double right, double bottom}) insets(
      WidgetTester tester) {
    final card = tester.renderObject<RenderBox>(find.byType(InkCard));
    final child = tester.renderObject<RenderBox>(find.byKey(childKey));
    final c0 = card.localToGlobal(Offset.zero);
    final k0 = child.localToGlobal(Offset.zero);
    return (
      left: k0.dx - c0.dx,
      top: k0.dy - c0.dy,
      right: (c0.dx + card.size.width) - (k0.dx + child.size.width),
      bottom: (c0.dy + card.size.height) - (k0.dy + child.size.height),
    );
  }

  Widget card({EdgeInsetsGeometry? padding, CardDensity? density}) => InkCard(
        padding: padding,
        density: density ?? CardDensity.normal,
        child: const SizedBox(key: childKey, height: 20, width: double.infinity),
      );

  /// Each density must render exactly what the hand-written padding it replaced
  /// rendered. The pairs are the real migrations: 11 sites moved off
  /// `EdgeInsets.zero`, 9 off `all(16)`, 4 off `all(12)`, 2 off `all(24)`.
  final migrations = <String, (EdgeInsets, CardDensity)>{
    'EdgeInsets.zero → flush': (EdgeInsets.zero, CardDensity.flush),
    'all(12) → dense': (const EdgeInsets.all(12), CardDensity.dense),
    'all(16) → normal': (const EdgeInsets.all(16), CardDensity.normal),
    'all(24) → roomy': (const EdgeInsets.all(24), CardDensity.roomy),
  };

  migrations.forEach((name, pair) {
    final (padding, density) = pair;
    testWidgets('$name moves the child by zero pixels', (tester) async {
      await pump(tester, card(padding: padding));
      final before = insets(tester);

      await pump(tester, card(density: density));
      final after = insets(tester);

      expect(after, before,
          reason: 'the migration was meant to be a rename, not a redesign');
    });
  });

  testWidgets('a card with no density stated renders the normal one',
      (tester) async {
    // The 9 sites that dropped `padding: const EdgeInsets.all(16)` altogether
    // rely on this: the default has to BE what they were passing.
    await pump(
        tester,
        const InkCard(child: SizedBox(key: childKey, height: 20, width: double.infinity)));
    final byDefault = insets(tester);

    await pump(tester, card(density: CardDensity.normal));
    expect(byDefault, insets(tester));
  });

  testWidgets('every density insets all four edges by the same amount',
      (tester) async {
    // A density is "how much air", one number. If any of them ever renders
    // asymmetrically, the name has stopped describing the thing.
    for (final d in CardDensity.values) {
      await pump(tester, card(density: d));
      final i = insets(tester);
      expect([i.left, i.top, i.right, i.bottom], everyElement(i.left),
          reason: 'CardDensity.${d.name} rendered a lopsided inset');
    }
  });

  testWidgets('the densities are strictly ordered, flush tightest',
      (tester) async {
    final measured = <double>[];
    for (final d in CardDensity.values) {
      await pump(tester, card(density: d));
      measured.add(insets(tester).top);
    }
    // Declaration order is the vocabulary an author reads; if `dense` ever
    // rendered roomier than `normal`, picking one by name would be a coin toss.
    for (var i = 1; i < measured.length; i++) {
      expect(measured[i], greaterThan(measured[i - 1]),
          reason: 'CardDensity.${CardDensity.values[i].name} is not roomier '
              'than CardDensity.${CardDensity.values[i - 1].name}');
    }
    expect(measured.first, 0,
        reason: 'flush exists so the child can pad its own sections');
  });

  testWidgets('the accent ridge keeps its clearance on the START edge in RTL',
      (tester) async {
    // The ridge is painted with `PositionedDirectional(start: 0)`, so the 4px
    // the padding adds for it has to move to the same edge the ridge did.
    Future<double> ridgeSide(TextDirection dir) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildBrandThemes().light,
        home: Directionality(
          textDirection: dir,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: InkCard(
                  ruleColor: const Color(0xFFE2AD25),
                  density: CardDensity.dense,
                  child: const SizedBox(key: childKey, height: 20, width: double.infinity),
                ),
              ),
            ),
          ),
        ),
      ));
      final i = insets(tester);
      return dir == TextDirection.ltr ? i.left : i.right;
    }

    final ltr = await ridgeSide(TextDirection.ltr);
    final rtl = await ridgeSide(TextDirection.rtl);
    expect(rtl, ltr,
        reason: 'Arabic is the primary locale; the ridge and its clearance '
            'must arrive at the same edge together');
    expect(ltr, greaterThan(CardDensity.dense.value),
        reason: 'the ridge is meant to ADD clearance, not sit under the text');
  });
}
