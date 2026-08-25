import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// Widest a white-label logo may render, as a multiple of its slot height
/// (UX-117). 4:1 covers a normal wordmark; anything wider is scaled down to fit
/// rather than allowed to push the account name out of the masthead. At the
/// full h=44 that is 176dp, inside the desktop sidebar's 236dp content width;
/// at the compact h=30 it is 120dp, inside a phone AppBar title.
const double _kLogoMaxAspect = 4.0;

/// The nav masthead for the signed-in session. When the account's Main-Agent
/// brand carries a logo, render THAT logo (plus the account name) so agents see
/// their own identity — not just a tint on the nav rows (B-046). Falls back to
/// the Inteshar star lockup for HQ and any account without a brand logo.
class BrandMasthead extends ConsumerWidget {
  final String fallbackTitle;
  final bool compact;
  final bool onBrandSurface;
  final bool showTagline;

  const BrandMasthead({
    super.key,
    required this.fallbackTitle,
    this.compact = false,
    this.onBrandSurface = false,
    this.showTagline = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final logoUrl = auth is AuthAuthenticated ? auth.brand.agentLogoUrl : '';
    final name = auth is AuthAuthenticated ? auth.entity.meta.name : '';

    final lockup = IntesharLockup(
      title: fallbackTitle,
      tagline: 'Inteshar',
      compact: compact,
      onBrandSurface: onBrandSurface,
      showTagline: showTagline,
    );
    if (logoUrl.isEmpty) return lockup;

    final cs = Theme.of(context).colorScheme;
    final fg = onBrandSurface ? cs.onPrimary : cs.onSurface;
    final h = compact ? 30.0 : 44.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // UX-117: this used to set only `height`, with no width bound and no
        // flex — so `BoxFit.contain` had nothing to contain against and a wide
        // wordmark rendered at its full aspect ratio. A 10:1 logo at h=44 is
        // 440dp of Row, against a ~190dp phone AppBar title budget and the
        // desktop sidebar's 236dp of content (280 minus the band's 2×22
        // padding). The account name beside it was squeezed out and the Row
        // overflowed. Bounding BOTH axes lets `contain` scale the logo down
        // instead; `Flexible` lets a tighter parent shrink it further. Height is
        // pinned so the masthead does not jump while the image loads.
        Flexible(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: h,
                maxHeight: h,
                maxWidth: h * _kLogoMaxAspect,
              ),
              child: Image.network(
                logoUrl,
                fit: BoxFit.contain,
                // A broken/blocked logo must never leave an empty masthead.
                errorBuilder: (_, _, _) => lockup,
              ),
            ),
          ),
        ),
        if (name.isNotEmpty) ...[
          const SizedBox(width: IntesharSpacing.sm2),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              maxLines: compact ? 1 : 2,
              // UX-140/UX-127: was `IntesharType.serif` (a pre-refactor alias of
              // sans) at an off-scale 15/18.
              style: compact
                  ? IntesharText.bodyLg(color: fg, w: IntesharWeight.heavy)
                  : IntesharText.title(color: fg, w: IntesharWeight.heavy),
            ),
          ),
        ],
      ],
    );
  }
}
