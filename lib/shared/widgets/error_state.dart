import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const ErrorState({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    // Friendly, localized message (backend message for 400/402/409, a keyed fallback for
    // auth/permission/server) — never a raw DioException / ApiException dump.
    final msg = friendlyError(error, context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: InkCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                StampPill(
                  label: l.errorStateErrorLabel,
                  color: cs.error,
                  icon: Icons.warning_amber_rounded,
                ),
                const SizedBox(height: 16),
                Text(
                  l.errorStateTitle,
                  style: IntesharText.titleLg(
                    color: cs.onSurface,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(IntesharSpacing.md),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(IntesharRadii.md),
                    border: Border.all(color: cs.outline),
                  ),
                  child: SelectableText(
                    msg,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: IntesharScale.body,
                      color: cs.onSurface,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: BrandCTAButton(
                    label: l.retryButton,
                    leading: Icons.refresh,
                    onPressed: onRetry,
                    expand: false,
                    height: 44,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
