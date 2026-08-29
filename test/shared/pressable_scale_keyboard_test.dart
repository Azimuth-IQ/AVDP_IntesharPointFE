import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// `PressableScale` wraps the POS selling tiles — the most-used control in the
/// product — and was a bare `GestureDetector`, i.e. reachable only by a finger.
///
/// These assert the three things that were missing, because none of them are
/// visible when you click the tile with a mouse: a keyboard user can reach it,
/// activate it, and a screen reader is told it is a button.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('Enter activates a focused tile', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(
      PressableScale(onTap: () => taps++, child: const Text('Sell')),
    ));

    Focus.of(tester.element(find.text('Sell'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('Space activates it too', (tester) async {
    // Space is what most people press on a focused button; supporting only
    // Enter is the kind of half-fix that reads as "keyboard support" and is not.
    var taps = 0;
    await tester.pumpWidget(host(
      PressableScale(onTap: () => taps++, child: const Text('Sell')),
    ));

    Focus.of(tester.element(find.text('Sell'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('an unrelated key does not fire the action', (tester) async {
    // A tile that sells a voucher must not go off because someone typed.
    var taps = 0;
    await tester.pumpWidget(host(
      PressableScale(onTap: () => taps++, child: const Text('Sell')),
    ));

    Focus.of(tester.element(find.text('Sell'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('a tile with no action is not a tab stop', (tester) async {
    await tester.pumpWidget(host(
      const PressableScale(child: Text('Inert')),
    ));

    final node = Focus.of(tester.element(find.text('Inert')));
    expect(node.canRequestFocus, isFalse,
        reason: 'tabbing through a grid must not stop on tiles that do nothing');
  });

  testWidgets('it is announced as a button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(
      PressableScale(onTap: () {}, child: const Text('Sell')),
    ));

    // hasTapAction/hasFocusAction are asserted, not merely tolerated: an
    // announced "button" that exposes neither is a label with nothing behind it.
    expect(
      tester.getSemantics(find.text('Sell')),
      matchesSemantics(
        label: 'Sell',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        // The whole point of the change: assistive tech is told this can take
        // focus, which is what makes it reachable without a pointer.
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  // ── UX-12: reachable BY TAB, and visible once you get there ───────────────

  testWidgets('Tab moves focus from one tile to the next', (tester) async {
    // The tests above call `requestFocus()` by hand, which proves the node
    // exists but not that the traversal ever visits it. This presses the actual
    // key a keyboard user presses.
    await tester.pumpWidget(host(Column(
      children: [
        PressableScale(onTap: () {}, child: const Text('A')),
        PressableScale(onTap: () {}, child: const Text('B')),
      ],
    )));

    final a = Focus.of(tester.element(find.text('A')));
    final b = Focus.of(tester.element(find.text('B')));
    a.requestFocus();
    await tester.pump();
    expect(a.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(b.hasFocus, isTrue,
        reason: 'Tab stepped straight past the next tile');
  });

  testWidgets('the focus ring is actually visible against the tile',
      (tester) async {
    // The ring was `cs.primary` — the raw brand gold, **2.05:1** on the white
    // tile it is painted over, i.e. a focus indicator you cannot find. WCAG puts
    // the floor for a non-text UI cue at 3:1, and this reads the colour the
    // DecoratedBox really paints rather than the token someone meant to use.
    final theme = buildBrandThemes().light;
    // The fill the real POS tiles use (`_SkuCard`, `_GovCard`, `_CompanyCard`).
    final tile = theme.colorScheme.surfaceContainer;

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: PressableScale(
            onTap: () {},
            // ColoredBox, not Container: a Container would add a second
            // DecoratedBox and the finder below would stop meaning anything.
            child: const ColoredBox(
              color: Color(0xFFFFFFFF),
              child: SizedBox(width: 120, height: 80, child: Text('Sell')),
            ),
          ),
        ),
      ),
    ));

    Focus.of(tester.element(find.text('Sell'))).requestFocus();
    await tester.pumpAndSettle();

    final painted = tester.renderObject<RenderDecoratedBox>(
      find.descendant(
        of: find.byType(PressableScale),
        matching: find.byType(DecoratedBox),
      ),
    );
    final border = (painted.decoration as BoxDecoration).border;
    expect(border, isNotNull, reason: 'a focused tile drew no ring at all');

    final ring = border!.top.color;
    expect(border.top.width, greaterThanOrEqualTo(2.0));
    expect(
      contrastRatio(ring, tile),
      greaterThanOrEqualTo(3.0),
      reason: 'the focus ring measures ${contrastRatio(ring, tile).toStringAsFixed(2)}:1 '
          'on the tile it is drawn over — invisible is not an indicator',
    );
  });

  testWidgets('an unfocused tile draws no ring', (tester) async {
    // Otherwise every tile in the grid would wear a border and the focused one
    // would be indistinguishable — the same failure by the opposite route.
    await tester.pumpWidget(host(
      PressableScale(onTap: () {}, child: const Text('Sell')),
    ));
    await tester.pumpAndSettle();

    final painted = tester.renderObject<RenderDecoratedBox>(
      find.descendant(
        of: find.byType(PressableScale),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((painted.decoration as BoxDecoration).border?.top.style,
        BorderStyle.none);
  });

  testWidgets('tapping still works and still fires once', (tester) async {
    // The keyboard path must not have cost the pointer path — this is a POS
    // tile, and a double-fire sells two vouchers.
    var taps = 0;
    await tester.pumpWidget(host(
      PressableScale(onTap: () => taps++, child: const Text('Sell')),
    ));

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
