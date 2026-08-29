import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// UX-121 — the report surface had ONE breakpoint (720), so a 1440dp browser
/// window drew the same finger-sized rows as a 760dp tablet.
///
/// The tier is picked from the width the TABLE was handed, not the viewport, so
/// the numbers that matter are the ones after the desktop chrome (280dp of
/// sidebar + 16dp of gutter each side) has been taken out. These pin the two
/// boundaries and the degenerate widths a `LayoutBuilder` really does hand out
/// mid-layout.
void main() {
  group('TableDensity.forWidth', () {
    test('a phone cannot carry columns', () {
      expect(TableDensity.forWidth(328), TableDensity.stacked);
      expect(TableDensity.forWidth(600), TableDensity.stacked);
    });

    test('the columns boundary is exact', () {
      expect(TableDensity.forWidth(719.9), TableDensity.stacked);
      expect(TableDensity.forWidth(720), TableDensity.comfortable);
    });

    test('the dense boundary is exact', () {
      expect(TableDensity.forWidth(1099.9), TableDensity.comfortable);
      expect(TableDensity.forWidth(1100), TableDensity.dense);
    });

    test('the viewports this item is actually about', () {
      // 1280 viewport − 280 sidebar − 32 gutters.
      expect(TableDensity.forWidth(968), TableDensity.comfortable);
      // 1440 — the case in the finding: "1440 gets the same rows as a 760dp
      // tablet". It must not any more.
      expect(TableDensity.forWidth(1128), TableDensity.dense);
      // 1920, capped at Breakpoints.contentWideMax.
      expect(TableDensity.forWidth(1568), TableDensity.dense);
    });

    test('degenerate widths fall back to the layout that needs no width', () {
      // NaN fails EVERY comparison, so a `>=` chain without an explicit guard
      // silently returns the widest tier for it.
      expect(TableDensity.forWidth(double.nan), TableDensity.stacked);
      expect(TableDensity.forWidth(0), TableDensity.stacked);
      expect(TableDensity.forWidth(-1), TableDensity.stacked);
    });
  });

  group('what each tier spends', () {
    test('only the desktop tier is denser than the tablet one', () {
      expect(TableDensity.dense.rowPadY,
          lessThan(TableDensity.comfortable.rowPadY));
      expect(TableDensity.stacked.rowPadY, TableDensity.comfortable.rowPadY,
          reason: 'a phone row is still touched, so it keeps finger padding');
    });

    test('the 44dp touch floor is kept wherever a finger might land', () {
      expect(TableDensity.comfortable.headerMinHeight, 44);
      expect(TableDensity.dense.headerMinHeight, lessThan(44),
          reason: 'a mouse does not need a 44dp target');
    });

    test('only the stacked tier is not a table', () {
      expect(TableDensity.stacked.tabular, isFalse);
      expect(TableDensity.comfortable.tabular, isTrue);
      expect(TableDensity.dense.tabular, isTrue);
    });
  });
}
