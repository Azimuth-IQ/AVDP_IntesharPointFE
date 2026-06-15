import 'package:flutter/material.dart';

/// Layout breakpoints used across the app.
///
/// - mobile: < 600
/// - tablet: 600–1199
/// - desktop: >= 1200
class Breakpoints {
  static const double tablet = 600;
  static const double desktop = 1200;
  static const double contentMax = 1280;
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
