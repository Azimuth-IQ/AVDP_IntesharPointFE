import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

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
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            logoUrl,
            height: h,
            fit: BoxFit.contain,
            // A broken/blocked logo must never leave an empty masthead.
            errorBuilder: (_, _, _) => lockup,
          ),
        ),
        if (name.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              maxLines: compact ? 1 : 2,
              style: IntesharType.serif(compact ? 15 : 18, color: fg, w: FontWeight.w800),
            ),
          ),
        ],
      ],
    );
  }
}
