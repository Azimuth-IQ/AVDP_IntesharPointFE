import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/data/login_brand.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// PROD-006: what the sign-in header shows right now — the device's remembered agent, Inteshar, or
/// nothing — from the remembered brand and HQ's switch.
({LoginHeaderMode mode, String logoUrl}) watchLoginHeader(WidgetRef ref) {
  final remembered = ref.watch(rememberedLoginBrandProvider).valueOrNull;
  final show = ref.watch(loginShowIntesharProvider).valueOrNull;
  return (
    mode: loginHeaderMode(remembered: remembered, showInteshar: show),
    logoUrl: remembered?.logoUrl ?? '',
  );
}

/// The agent's logo in place of the Inteshar lockup. A logo that fails to load leaves the space
/// empty rather than falling back to Inteshar, which is the brand this replaces.
class _AgentLogo extends StatelessWidget {
  final String url;
  final double height;
  const _AgentLogo({required this.url, required this.height});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Image.network(
        url,
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'logo',
        errorBuilder: (_, _, _) => SizedBox(height: height),
      ),
    ),
  );
}

/// Wide layouts: the brand half beside the sign-in form (B-094 layout, unchanged for Inteshar).
class LoginBrandPanel extends ConsumerWidget {
  const LoginBrandPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = watchLoginHeader(ref);
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tones = context.tones;
    return GestureDetector(
      onLongPress: () => context.push('/diagnostics'),
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: cs.surface,
        // B-094: centre a fixed-width brand block in this half rather than letting
        // it hug the outer edge — with the form centred in the other half, edge-
        // aligning here opened a dead channel down the middle of the page.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
              child: switch (h.mode) {
                LoginHeaderMode.agent => _AgentLogo(url: h.logoUrl, height: 96),
                LoginHeaderMode.neutral => const SizedBox.shrink(),
                LoginHeaderMode.inteshar => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IntesharStar(size: 44, color: tones.brand),
                    const SizedBox(height: IntesharSpacing.xxl),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'Inteshar',
                        style: TextStyle(
                          fontFamily: 'CodecPro',
                          color: cs.onSurface,
                          fontSize: 76,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2.6,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // The one deliberate flash of brand colour on the panel.
                    Container(width: 56, height: 3, color: tones.brand),
                    const SizedBox(height: 20),
                    Text(
                      l.loginBrandTagline,
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        color: cs.onSurfaceVariant,
                        fontSize: 16.5,
                        height: 1.55,
                        // w500 is not a CodecPro face; it always rendered as Regular (w400).
                        fontWeight: IntesharWeight.regular,
                      ),
                    ),
                  ],
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// B-094: the mobile sign-in header — white, compact, typographic. Replaces the
/// gold band that dominated the first screen every operator sees.
class LoginMobileBrandHeader extends ConsumerWidget {
  const LoginMobileBrandHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = watchLoginHeader(ref);
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tones = context.tones;
    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
        child: switch (h.mode) {
          LoginHeaderMode.agent => _AgentLogo(url: h.logoUrl, height: 56),
          // Keeps the form where it always sits, with nothing branded above it.
          LoginHeaderMode.neutral => const SizedBox(height: 56),
          LoginHeaderMode.inteshar => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IntesharStar(size: 30, color: tones.brand),
                  const SizedBox(width: IntesharSpacing.md),
                  Text(
                    'Inteshar',
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      color: cs.onSurface,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: IntesharSpacing.sm2),
              Text(
                l.loginBrandTaglineShort,
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  // w500 is not a CodecPro face; it always rendered as Regular (w400).
                  fontWeight: IntesharWeight.regular,
                  height: 1.4,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}
