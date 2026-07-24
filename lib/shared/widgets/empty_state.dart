import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// Friendly empty state: a low-alpha brand star above the message and an
/// optional CTA in the brand pill style.
class EmptyState extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: 0.25,
                child: IntesharStar(size: 64, color: context.tones.brandInk),
              ),
              const SizedBox(height: 18),
              Text(
                l.emptyStateTitle,
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                BrandCTAButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  expand: false,
                  height: 44,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
