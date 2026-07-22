import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_band.dart';
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

    return Scaffold(
      body: GestureDetector(
        onLongPress: () => context.push('/diagnostics'),
        child: BrandBand(
          padding: EdgeInsets.zero,
          sparkleSize: 420,
          sparkleAlignment: const Alignment(1.4, -1.3),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IntesharStar(size: 96, color: IntesharColors.ink),
                  const SizedBox(height: 28),
                  Text(
                    l.appTitle,
                    style: IntesharType.display(46, color: IntesharColors.ink, w: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.splashTagline,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      color: IntesharColors.ink.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: IntesharColors.ink,
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
