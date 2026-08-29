import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';

/// Layout breakpoints used across the app.
///
/// - mobile: < 600
/// - tablet: 600–1199
/// - desktop: >= 1200
class Breakpoints {
  static const double tablet = 600;
  static const double desktop = 1200;

  /// Reading width for PROSE-shaped content — a form, a settings page, a
  /// conversation. Long measure hurts reading, so the cap is real here.
  static const double contentMax = 1280;

  /// Reading width for TABULAR / comparison content (UX-13, UX-121).
  ///
  /// [contentMax] is a *typographic* limit and it is being applied to data. The
  /// HQ console is used on a 1080p browser: 1920 − 280 of sidebar leaves ~1640dp
  /// of usable width, of which 1280 is used and ~360 is thrown away, and inside
  /// that the agent list still renders one column of tall cards — about five
  /// agents on screen at once, each mostly white space. A price list, an agent
  /// roster and a log feed are not prose; they are meant to be COMPARED down a
  /// column, and every row you have to scroll for is a comparison you cannot
  /// make.
  ///
  /// Use this (with [AdaptiveColumns]) for anything the reader scans; keep
  /// [contentMax] for anything they read.
  static const double contentWideMax = 1600;

  static const double formMax = 560;
}

enum ScreenSize { mobile, tablet, desktop }

/// How much air a DATA TABLE gives each of its rows (UX-121).
///
/// The report surface had exactly one breakpoint — 720 — so a 1440dp browser
/// window rendered the same rows as a 760dp tablet: 12dp of padding above and
/// below every line, sized for a fingertip, on a screen nobody touches. The HQ
/// console is a full-time mouse workload; a third of the vertical space in the
/// table was being spent on a target that no longer needs to be 44dp.
///
/// The tier is decided from the width the **table itself** was handed, not the
/// viewport, because that is the number that decides what fits. On the desktop
/// shell the chrome costs a fixed 280dp of sidebar plus 16dp of gutter each
/// side, so:
///
/// | viewport | table width | tier |
/// |----------|-------------|------|
/// | 360      | 328         | [stacked] |
/// | 1024     | 712         | [stacked] — one pixel short of columns |
/// | 1280     | 968         | [comfortable] |
/// | 1440     | 1128        | [dense] |
/// | 1920     | 1568 (capped at [Breakpoints.contentWideMax]) | [dense] |
///
/// Density here is spent on **padding, not type**: shrinking the figures would
/// buy more rows and cost the legibility the type scale was tuned for.
enum TableDensity {
  /// Below [columnsFrom] — no room for aligned columns at all, so a record
  /// stacks onto two lines instead. Finger padding, because this is the phone.
  stacked(rowPadY: IntesharSpacing.md, headerMinHeight: 0),

  /// The tablet table: real columns, rows still sized for a fingertip.
  comfortable(rowPadY: IntesharSpacing.md, headerMinHeight: 44),

  /// The desktop table. Row padding drops a step and the header loses the 44dp
  /// touch floor (a mouse does not need it), which is ~19% more rows per screen
  /// — four extra agents on a 900dp-tall viewport.
  dense(rowPadY: IntesharSpacing.sm, headerMinHeight: 36);

  const TableDensity({required this.rowPadY, required this.headerMinHeight});

  /// Padding above and below a data row.
  final double rowPadY;

  /// Floor on the column-header cell — it is also the sort control's hit area,
  /// so it is a tap target, not decoration (UX-119).
  final double headerMinHeight;

  /// Narrowest width that can carry aligned columns.
  static const double columnsFrom = 720;

  /// Narrowest width that is unambiguously a desktop browser rather than a
  /// tablet held in two hands.
  static const double denseFrom = 1100;

  /// True when the tier renders real columns rather than stacked lines.
  bool get tabular => this != TableDensity.stacked;

  /// The tier for a table [width]. Degenerate widths (0 and NaN both arrive
  /// from a transient layout pass) fall back to the safest layout, which is the
  /// one that needs no width at all.
  static TableDensity forWidth(double width) {
    if (width.isNaN || width < columnsFrom) return stacked;
    return width >= denseFrom ? dense : comfortable;
  }
}

extension ResponsiveBuildContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  ScreenSize get screenSize {
    final w = screenWidth;
    if (w >= Breakpoints.desktop) return ScreenSize.desktop;
    if (w >= Breakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.mobile;
  }

  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;
  bool get isCompact => isMobile;
  bool get isWide => !isMobile;
}

/// Constrains its [child] to [maxWidth] and centers it. Useful for keeping
/// list/form readability bounded on very wide screens.
///
/// For a screen whose content is tabular rather than prose, pass
/// `maxWidth: Breakpoints.contentWideMax` — or use [MaxWidthBox.wide], which
/// says the same thing at the call site (UX-13).
class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentMax,
    this.padding = EdgeInsets.zero,
  });

  /// The data-density variant: [Breakpoints.contentWideMax] instead of the
  /// prose cap. Use on rosters, price lists, inventories, logs.
  const MaxWidthBox.wide({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  }) : maxWidth = Breakpoints.contentWideMax;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Lays [children] out in as many columns as the width honestly allows (UX-13).
///
/// The problem this solves is one narrow column of tall cards on a 1080p
/// browser: ~1640dp of usable width showing about five agents, each mostly white
/// space, so "which agent has the fewest POS points?" needs scrolling — and a
/// comparison you have to scroll for is one you cannot make.
///
/// Deliberately NOT a `GridView`. These are cards of genuinely different heights
/// (an agent with three governorate pills is taller than one with a single
/// governorate), and a grid forces a row to the tallest cell, reinstating the
/// white space this exists to remove. Children are dealt round-robin into
/// independent columns instead, so each column packs to its own content.
///
/// Round-robin also preserves READING order across the columns: with three
/// columns the sequence runs 1,2,3 across the first row of cards, then 4,5,6 —
/// the order the eye expects. Filling column-by-column would put items 1..n in
/// the first column, which reads as three unrelated lists.
///
/// Collapses to a single [Column] below [minColumnWidth] * 2, so a phone and a
/// narrow tablet keep the layout they already have.
class AdaptiveColumns extends StatelessWidget {
  final List<Widget> children;

  /// The narrowest a column may become before dropping one. Cards below roughly
  /// 320dp start wrapping their own content, which costs more vertical space
  /// than the extra column saves.
  final double minColumnWidth;

  /// Ceiling on columns. Three is the practical maximum for a card carrying a
  /// name, a metric row and a chip row — beyond that the card is narrower than
  /// its own content and every line wraps.
  final int maxColumns;

  final double spacing;

  const AdaptiveColumns({
    super.key,
    required this.children,
    this.minColumnWidth = 360,
    this.maxColumns = 3,
    this.spacing = IntesharSpacing.md,
  });

  /// How many columns [width] supports — exposed for tests and callers that need
  /// to know the count before building (e.g. to pick a denser row layout).
  int columnsFor(double width) {
    if (width.isNaN || width <= 0) return 1;
    // Every column after the first also costs a gap.
    final n = ((width + spacing) / (minColumnWidth + spacing)).floor();
    return n.clamp(1, maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = columnsFor(constraints.maxWidth);
        if (count <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        final columns = List.generate(count, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          columns[i % count].add(children[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < count; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns[c].length; i++) ...[
                      if (i > 0) SizedBox(height: spacing),
                      columns[c][i],
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
