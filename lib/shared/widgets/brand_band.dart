import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// A yellow-surface hero container. Used as the masthead band on screens
/// where the brand should set the first impression (splash, login left
/// panel, dashboard top, sidebar header, grand-total summary).
///
/// Renders an optional decorative star in a corner at low opacity for
/// the "linen-textured sunburst" feel of the brand image.
///
/// That star is INTESHAR's OWN mark, so it is drawn only for HQ and for the
/// signed-out brand screens. On a white-labelled account it sat behind the
/// agent's logo, in the agent's colour, and no amount of branding would shift
/// it — which is precisely what the client reported on 2026-09-26 ("اللوكو
/// الخلفي مجاي يتغير", the background logo doesn't change). The POS already
/// passed `sparkle: false` by hand for this reason; deciding it here means the
/// rule holds on every band instead of the one somebody remembered.
class BrandBand extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Defaults to the SESSION's brand colour so a white-label band isn't gold (B-085).
    final bg = background ?? Theme.of(context).colorScheme.primary;
    // Signed out (splash, login) the band is Inteshar's own, so it keeps the star.
    final auth = ref.watch(authStateProvider).valueOrNull;
    final isPlatform =
        auth is! AuthAuthenticated || auth.entity.type == EntityType.INTESHAR;
    final showSparkle = sparkle && isPlatform;
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
      child: showSparkle
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
