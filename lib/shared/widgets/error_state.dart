import 'package:flutter/material.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const ErrorState({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final msg = error.toString().replaceFirst('ApiException', 'Error').replaceAll(RegExp(r'\(\d+\): '), ': ');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(msg, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l.retryButton)),
          ],
        ),
      ),
    );
  }
}
