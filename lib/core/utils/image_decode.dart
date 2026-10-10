import 'package:flutter/widgets.dart';

/// How many physical pixels to decode a network image at, so it is drawn at
/// [logical] dp on this screen.
///
/// Every `Image.network` in the app used to decode at the size it was UPLOADED.
/// Admins upload phone photos and print-quality logos, so a logo shown 26 dp tall
/// in the POS app bar was decoded as a multi-megapixel bitmap — on a POS handheld
/// with a single-core GPU and 2–3 GB of RAM, that is decode time on the way in,
/// texture upload on every first paint, and memory pressure that the garbage
/// collector pays for later. Passing the result as `cacheWidth`/`cacheHeight`
/// makes the engine decode straight to the drawn size (aspect ratio is kept when
/// only one of the two is given).
///
/// [minRatio] raises the floor for images that are captured to a bitmap at a
/// fixed ratio (the receipt preview is snapshotted at 3×) rather than only shown.
int decodePx(BuildContext context, double logical, {double minRatio = 0}) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
  final ratio = dpr < minRatio ? minRatio : dpr;
  final px = (logical * ratio).ceil();
  return px < 1 ? 1 : (px > 2048 ? 2048 : px);
}
