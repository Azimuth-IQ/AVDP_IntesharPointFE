import 'package:flutter/material.dart';

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
  /// Use this (with [CompactTable] or [AdaptiveColumns]) for anything the reader
  /// scans; keep [contentMax] for anything they read.
  static const double contentWideMax = 1600;

  static const double formMax = 560;
}

enum ScreenSize { mobile, tablet, desktop }

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
