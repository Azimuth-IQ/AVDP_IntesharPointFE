import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// UX-12 — [InkCard] is the app's list row, and a keyboard user could not see
/// which one they were on.
///
/// The row was never *unreachable*: `InkWell` is a tab stop out of the box. But
/// its focus highlight is `Theme.focusColor` painted as ink on the `Material`
/// under the child, and the child is an opaque tile — so the highlight was
/// drawn and then covered up. That is the identical failure UX-121 found for
/// hover, and the fix is the same shape: put the signal in the tile's own
/// decoration.
///
/// These press the real Tab key and read the colour actually painted, so they
/// fail if the ring goes back to an overlay, loses its contrast, or starts
/// showing on rows that do nothing.
void main() {
  final theme = buildBrandThemes().light;

  Future<void> pump(
    WidgetTester tester, {
    required bool interactive,
    int count = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Column(
          children: [
            for (var i = 0; i < count; i++)
              InkCard(
                onTap: interactive ? () {} : null,
                child: Text('row $i'),
              ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The ring row [index] is really painting, or null when it draws none.
  ///
  /// Scoped to that row's own subtree on purpose: an `AnimatedContainer` builds
  /// no foreground box at all while the decoration is null, so indexing a flat
  /// list of foreground boxes would silently read the *other* row's ring.
  BoxDecoration? ring(WidgetTester tester, int index) {
    final boxes = tester
        .renderObjectList<RenderDecoratedBox>(find.descendant(
          of: find.byType(InkCard).at(index),
          matching: find.byType(DecoratedBox),
        ))
        .where((b) => b.position == DecorationPosition.foreground)
        .toList();
    if (boxes.isEmpty) return null;
    return boxes.first.decoration as BoxDecoration?;
  }

  testWidgets('a row shows nothing until it is focused', (tester) async {
    await pump(tester, interactive: true);
    expect(ring(tester, 0)?.border, isNull);
  });

  testWidgets('Tab focuses the row and draws a visible ring', (tester) async {
    await pump(tester, interactive: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final border = ring(tester, 0)?.border;
    expect(border, isNotNull,
        reason: 'Tab reached the row and nothing on screen said so');

    final surface = theme.colorScheme.surfaceContainer;
    final colour = border!.top.color;
    expect(
      contrastRatio(colour, surface),
      greaterThanOrEqualTo(3.0),
      reason: 'ring measures ${contrastRatio(colour, surface).toStringAsFixed(2)}:1 '
          'against the row it is drawn on',
    );
    expect(border.top.width, greaterThanOrEqualTo(2.0));
  });

  testWidgets('the ring follows Tab down the list', (tester) async {
    // One row permanently ringed would be worse than none — the indicator has
    // to mean "here", not "somewhere".
    await pump(tester, interactive: true, count: 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(ring(tester, 0)?.border, isNotNull);
    expect(ring(tester, 1)?.border, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(ring(tester, 0)?.border, isNull);
    expect(ring(tester, 1)?.border, isNotNull);
  });

  testWidgets('a row with no action is never focused or ringed',
      (tester) async {
    await pump(tester, interactive: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(ring(tester, 0)?.border, isNull);
  });
}
