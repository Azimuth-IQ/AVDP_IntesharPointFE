import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// UX-121 — a tappable [InkCard] had no pointer feedback at all.
///
/// It looked like it did: the `InkWell` sets `splashColor` and `highlightColor`.
/// But ink paints on the `Material` *beneath* the InkWell's child, and that
/// child is an opaque tile — so every one of those overlays was drawn and then
/// covered up. The feedback has to be in the tile's own decoration, and that is
/// what these read: the colour the `DecoratedBox` actually paints, after the
/// transition has settled, not the flag that was set.
void main() {
  /// The fill the card really paints right now.
  Color? paintedFill(WidgetTester tester) {
    final box = tester
        .renderObjectList<RenderDecoratedBox>(find.descendant(
          of: find.byType(AnimatedContainer),
          matching: find.byType(DecoratedBox),
        ))
        .first;
    return (box.decoration as BoxDecoration).color;
  }

  Future<void> pump(WidgetTester tester, {VoidCallback? onTap}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildBrandThemes().light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: InkCard(onTap: onTap, child: const Text('agent')),
          ),
        ),
      ),
    ));
  }

  /// A mouse parked off the card, ready to be moved onto it.
  Future<TestGesture> mouse(WidgetTester tester) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await tester.pump();
    return g;
  }

  testWidgets('a tappable card changes fill under a mouse', (tester) async {
    await pump(tester, onTap: () {});
    final resting = paintedFill(tester);

    final g = await mouse(tester);
    await g.moveTo(tester.getCenter(find.byType(InkCard)));
    await tester.pumpAndSettle();

    expect(paintedFill(tester), isNot(resting),
        reason: 'nothing on the card said it could be clicked');
  });

  testWidgets('and returns to rest when the pointer leaves', (tester) async {
    await pump(tester, onTap: () {});
    final resting = paintedFill(tester);

    final g = await mouse(tester);
    await g.moveTo(tester.getCenter(find.byType(InkCard)));
    await tester.pumpAndSettle();
    await g.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(paintedFill(tester), resting);
  });

  testWidgets('a card with no action does NOT react — it promises nothing',
      (tester) async {
    await pump(tester);
    final resting = paintedFill(tester);

    final g = await mouse(tester);
    await g.moveTo(tester.getCenter(find.byType(InkCard)));
    await tester.pumpAndSettle();

    expect(paintedFill(tester), resting);
  });

  testWidgets('a finger never triggers the hover state', (tester) async {
    // The POS is a touch device: a tap that left the card tinted would read as
    // a selection that never clears.
    var taps = 0;
    await pump(tester, onTap: () => taps++);
    final resting = paintedFill(tester);

    await tester.tap(find.byType(InkCard));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(paintedFill(tester), resting);
  });
}
