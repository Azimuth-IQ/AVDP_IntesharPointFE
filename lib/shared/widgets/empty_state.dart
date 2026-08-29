import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// The app's one "there is nothing here" state (UX-134).
///
/// There were 24 local variants against 16 uses of this one — the canonical
/// widget was the minority. `system_activity_page._NoticeState` is line-for-line
/// this class with an icon instead of the star; `reports_page` carries two
/// different empty styles in a single file; ten more are inline copies. Their
/// icons run 32/40/44/48/52.
///
/// So the shape is fixed here — centred, ≤360 wide, star or icon, bold title,
/// muted message, optional brand CTA — and the only knobs are the ones the
/// local copies actually needed:
///
/// - [icon] swaps the brand star for a glyph at one canonical size (that is all
///   `_NoticeState` was);
/// - [title] overrides the default "لا توجد بيانات" heading;
/// - [dense] tightens it for a card body or a sheet, instead of a page.
class EmptyState extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Heading above [message]. Defaults to the localized generic empty title.
  final String? title;

  /// Show this glyph instead of the low-alpha brand star.
  final IconData? icon;

  /// Leading glyph on the action button.
  final IconData? actionIcon;

  /// Tighter padding + smaller mark, for an empty state inside a card, a sheet
  /// or a tab body rather than a whole page.
  final bool dense;

  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.title,
    this.icon,
    this.actionIcon,
    this.dense = false,
  });

  /// One size for the mark, whether it is the star or a glyph.
  static const double markSize = 56;
  static const double denseMarkSize = 40;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final size = dense ? denseMarkSize : markSize;
    final heading = title ?? l?.emptyStateTitle;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: EdgeInsets.all(dense ? 20 : 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null)
                Icon(icon, size: size, color: cs.onSurfaceVariant)
              else
                Opacity(
                  opacity: 0.25,
                  child: IntesharStar(size: size, color: context.tones.brandInk),
                ),
              SizedBox(height: dense ? 12 : 18),
              if (heading != null) ...[
                Text(
                  heading,
                  textAlign: TextAlign.center,
                  // UX-127: was an off-scale 15 / 17.
                  style: dense
                      ? IntesharText.bodyLg(
                          color: cs.onSurface,
                          w: IntesharWeight.heavy,
                          letterSpacing: -0.2,
                        )
                      : IntesharText.title(
                          color: cs.onSurface,
                          w: IntesharWeight.heavy,
                          letterSpacing: -0.2,
                        ),
                ),
                const SizedBox(height: IntesharSpacing.sm),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: dense ? 14 : 18),
                BrandCTAButton(
                  label: actionLabel!,
                  leading: actionIcon,
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
