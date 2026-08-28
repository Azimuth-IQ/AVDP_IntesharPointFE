import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// UX-13 — the wide-desktop column count.
///
/// The arithmetic is where this quietly fails: forget that each extra column
/// also costs a gap and you claim a column that does not fit, so every card
/// wraps and the layout is worse than the single column it replaced. These
/// assert the boundaries rather than the middle of each band.
void main() {
  const w = AdaptiveColumns(children: [], minColumnWidth: 360, spacing: 12);

  group('column count', () {
    test('a phone gets one column', () {
      expect(w.columnsFor(360), 1);
      expect(w.columnsFor(414), 1);
    });

    test('two columns need both widths AND the gap between them', () {
      // 360 + 12 + 360 = 732 exactly.
      expect(w.columnsFor(731), 1, reason: 'one pixel short is still one column');
      expect(w.columnsFor(732), 2);
    });

    test('three columns likewise', () {
      // 360*3 + 12*2 = 1104.
      expect(w.columnsFor(1103), 2);
      expect(w.columnsFor(1104), 3);
    });

    test('it never exceeds maxColumns however wide the screen', () {
      // A card narrower than its own content wraps every line, which costs more
      // vertical space than the extra column saves.
      expect(w.columnsFor(4000), 3);
      expect(w.columnsFor(10000), 3);
    });

    test('degenerate widths do not produce zero or negative columns', () {
      // LayoutBuilder can hand out 0 during a transient layout pass; returning 0
      // would divide by zero downstream and returning -1 would throw.
      expect(w.columnsFor(0), 1);
      expect(w.columnsFor(-50), 1);
      expect(w.columnsFor(double.nan), 1);
    });

    test('the 1080p console case the item describes', () {
      // 1920 minus ~280 of sidebar, capped at contentWideMax.
      expect(w.columnsFor(1640), 3,
          reason: 'this is the screen that was showing ~5 agents in one column');
    });
  });

  group('layout', () {
    Future<void> pump(WidgetTester tester, double width, int n) async {
      // The default test surface is 800dp, and a SizedBox is clamped by its
      // parent's constraints — so asking for 1200 inside it silently gives 800
      // and the widget is judged on a width it never had. Size the view itself.
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdaptiveColumns(
            minColumnWidth: 360,
            spacing: 12,
            children: [for (var i = 0; i < n; i++) Text('card$i')],
          ),
        ),
      ));
    }

    testWidgets('every child is rendered exactly once', (tester) async {
      await pump(tester, 1200, 7);
      for (var i = 0; i < 7; i++) {
        expect(find.text('card$i'), findsOneWidget);
      }
    });

    testWidgets('reading order runs ACROSS the columns, not down them',
        (tester) async {
      // Round-robin: with 3 columns, 0/1/2 sit side by side on the first row.
      // Filling column-by-column would put 0,1,2 stacked in column one, which
      // reads as three unrelated lists.
      await pump(tester, 1200, 6);
      final x0 = tester.getTopLeft(find.text('card0')).dx;
      final x1 = tester.getTopLeft(find.text('card1')).dx;
      final x2 = tester.getTopLeft(find.text('card2')).dx;
      final y0 = tester.getTopLeft(find.text('card0')).dy;
      final y1 = tester.getTopLeft(find.text('card1')).dy;
      expect(x0 < x1 && x1 < x2, isTrue, reason: 'first three go across');
      expect(y0, y1, reason: 'and share a row');
      // The fourth wraps under the first.
      expect(tester.getTopLeft(find.text('card3')).dx, x0);
      expect(tester.getTopLeft(find.text('card3')).dy, greaterThan(y0));
    });

    testWidgets('a narrow viewport keeps the single-column layout', (tester) async {
      await pump(tester, 400, 3);
      final x0 = tester.getTopLeft(find.text('card0')).dx;
      expect(tester.getTopLeft(find.text('card1')).dx, x0);
      expect(tester.getTopLeft(find.text('card2')).dx, x0);
    });

    testWidgets('an empty list renders nothing rather than an empty Row',
        (tester) async {
      await pump(tester, 1200, 0);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('fewer children than columns still lays out', (tester) async {
      // Two cards on a three-column screen must not create an empty third
      // column that steals a third of the width from each.
      await pump(tester, 1200, 2);
      expect(find.text('card0'), findsOneWidget);
      expect(find.text('card1'), findsOneWidget);
    });
  });
}
