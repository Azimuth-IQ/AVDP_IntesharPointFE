import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
