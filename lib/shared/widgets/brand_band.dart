import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// A yellow-surface hero container. Used as the masthead band on screens
/// where the brand should set the first impression (splash, login left
/// panel, dashboard top, sidebar header, grand-total summary).
///
/// Renders an optional decorative star in a corner at low opacity for
/// the "linen-textured sunburst" feel of the brand image.
class BrandBand extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry? borderRadius;
  final bool sparkle;
  final double sparkleSize;
  final Alignment sparkleAlignment;
  final Color? background;

  const BrandBand({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(28, 28, 28, 28),
    this.borderRadius,
    this.sparkle = true,
    this.sparkleSize = 220,
    this.sparkleAlignment = const Alignment(1.05, 1.05),
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    // Defaults to the SESSION's brand colour so a white-label band isn't gold (B-085).
    final bg = background ?? Theme.of(context).colorScheme.primary;
    final content = Padding(padding: padding, child: child);

    final body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bg,
            // Subtle bottom darkening matches the linen-texture brand image.
            Color.lerp(bg, IntesharColors.ink, 0.06)!,
          ],
        ),
        borderRadius: borderRadius,
      ),
      child: sparkle
          ? Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: borderRadius is BorderRadius
                        ? borderRadius as BorderRadius
                        : BorderRadius.zero,
                    child: Align(
                      alignment: sparkleAlignment,
                      child: Opacity(
                        opacity: 0.12,
                        child: IntesharStar(
                          size: sparkleSize,
                          // Track the on-brand ink so the decorative star stays
                          // visible on a dark white-label band too (B-085).
                          color: Theme.of(context).colorScheme.onPrimary,
                          tilt: -0.32,
                        ),
                      ),
                    ),
                  ),
                ),
                content,
              ],
            )
          : content,
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius! as BorderRadius,
        child: body,
      );
    }
    return body;
  }
}
