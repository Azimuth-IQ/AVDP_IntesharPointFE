import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/utils/image_decode.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// PROD-025 (the client's example, 22 Nov): a POS home tile is the picture, edge to edge, with only
/// the name under it — for a company and for a card type alike. The price, the "available" line and
/// the Sell button left the card-type tile: a tap opens the sale sheet, which shows the price and the
/// total before anything is sold (and PROD-013 already keeps stock counts off every screen).

/// The picture's height is this share of the tile's width (4:3, as in the example).
const double kPosTilePictureRatio = 0.75;

/// The band under the picture: room for two lines of the name, so «آسياسيل ٥٠٠٠ دينار» never loses
/// its denomination (UX-52).
const double kPosTileBandHeight = 50;

/// Columns of both POS grids (companies, then a company's card types). Three on a phone-sized
/// terminal, as the client asked on 2026-09-28 and as in the example.
int posGridColumns(ScreenSize size) => switch (size) {
      ScreenSize.desktop => 4,
      ScreenSize.tablet => 3,
      ScreenSize.mobile => 3,
    };

/// Row height for a POS grid [width] wide with [columns] columns and [spacing] between them.
double posTileExtent(double width, int columns, {double spacing = 12}) {
  final tileWidth = (width - spacing * (columns - 1)) / columns;
  return tileWidth * kPosTilePictureRatio + kPosTileBandHeight;
}

class PosPictureTile extends StatelessWidget {
  final String name;
  final String? imageUrl;

  /// Null = the tile cannot be tapped (the shop's balance does not cover one card).
  final VoidCallback? onTap;

  /// The most logical width the picture is drawn at — the decode size (see decodePx).
  final double decodeWidth;

  /// Drawn in the picture's place when there is no picture, or it fails to load.
  final Widget fallback;

  /// A short warning over the picture (e.g. «الرصيد لا يكفي»); the tile is washed out with it.
  final String? notice;

  const PosPictureTile({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    required this.decodeWidth,
    required this.fallback,
    this.notice,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = (imageUrl ?? '').trim();
    final blocked = notice != null;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: blocked ? '$name — $notice' : name,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: blocked ? cs.surfaceContainerHighest : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(IntesharRadii.lg),
            boxShadow: blocked ? const [] : IntesharShadows.elev1,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url.isEmpty)
                      fallback
                    else
                      // White under the picture: company logos are drawn for a white page, and a
                      // transparent PNG must not pick up the dark theme's surface.
                      ColoredBox(
                        color: Colors.white,
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          cacheWidth: decodePx(context, decodeWidth),
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => fallback,
                          loadingBuilder: (ctx, child, progress) =>
                              progress == null ? child : ColoredBox(color: cs.surfaceContainerHighest),
                        ),
                      ),
                    if (blocked) ...[
                      // Washed out rather than an Opacity layer: the cashier must still read which
                      // card it is, and Opacity costs a saveLayer on the POS terminals' GPUs.
                      const ColoredBox(color: Color(0x80FFFFFF)),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Center(child: _Notice(text: notice!)),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: kPosTileBandHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Center(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: IntesharType.codec(
                        color: cs.onSurface,
                        size: 14,
                        height: 1.15,
                        w: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    final warn = context.status.warn;
    // Two lines rather than an ellipsis: on a 100 dp tile «الرصيد لا يكفي» does not fit on one.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        border: Border.all(color: warn),
      ),
      child: Text(
        text,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: IntesharType.codec(size: 11, height: 1.15, w: FontWeight.w800, color: warn),
      ),
    );
  }
}

/// No company logo: the brand colour fills the picture area, with the company's first letter.
class PosLetterArt extends StatelessWidget {
  final String name;
  const PosLetterArt({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mid = Color.lerp(cs.primary, cs.onPrimaryContainer, 0.5)!;
    final letter = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.onPrimaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(letter, style: IntesharType.display(36, color: legibleOn(mid), w: IntesharWeight.black)),
    );
  }
}
