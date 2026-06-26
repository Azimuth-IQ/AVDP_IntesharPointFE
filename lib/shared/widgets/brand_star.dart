import 'package:flutter/material.dart';

/// The Inteshar mark — the official comet-star logo
/// (`assets/images/brand_star.png`, extracted from the brand guidelines).
///
/// The asset is a gold silhouette on a transparent field. Pass [color] to tint
/// it for reversed / on-band usage (e.g. `cs.onSurface` for a mono mark, or
/// `IntesharColors.ink` on a gold band); leave it null to render the logo in
/// its own brand gold. The tint is applied with `BlendMode.srcIn`, so the
/// silhouette's anti-aliased edges are preserved.
class IntesharStar extends StatelessWidget {
  final double size;
  final Color? color;

  /// Retained for source compatibility; the raster mark is always solid.
  final bool filled;

  /// Extra lean in radians. The logo already leans, so this defaults to 0.
  final double tilt;

  const IntesharStar({
    super.key,
    this.size = 36,
    this.color,
    this.filled = false,
    this.tilt = 0,
  });

  @override
  Widget build(BuildContext context) {
    Widget mark = Image.asset(
      'assets/images/brand_star.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
    );
    if (tilt != 0) {
      mark = Transform.rotate(angle: tilt, child: mark);
    }
    return SizedBox(width: size, height: size, child: mark);
  }
}
