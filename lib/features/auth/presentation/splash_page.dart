import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authStateProvider, (_, next) {
      if (next.hasValue) {
        final s = next.value!;
        if (s is AuthAuthenticated) context.go(s.homeRoute);
        if (s is AuthUnauthenticated) context.go('/login');
      }
    });

    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tones = context.tones;

    // B-094: the FIRST screen anyone sees is now white, not a full gold band —
    // the brand reads through the mark and the wordmark, not a wall of colour.
    return Scaffold(
      backgroundColor: cs.surface,
      body: GestureDetector(
        onLongPress: () => context.push('/diagnostics'),
        child: SizedBox.expand(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IntesharStar(size: 72, color: tones.brand),
                  const SizedBox(height: 26),
                  Text(
                    l.appTitle,
                    style: IntesharType.display(44, color: cs.onSurface, w: FontWeight.w900),
                  ),
                  const SizedBox(height: IntesharSpacing.sm2),
                  Text(
                    l.splashTagline,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: tones.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
