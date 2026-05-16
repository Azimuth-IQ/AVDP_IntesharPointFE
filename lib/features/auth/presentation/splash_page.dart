import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';

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
        onLongPress: () => context.go('/diagnostics'),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store, size: 80, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(l.appTitle, style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Voucher Distribution', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.secondary)),
              const SizedBox(height: 32),
              const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3)),
            ],
          ),
        ),
      ),
    );
  }
}
