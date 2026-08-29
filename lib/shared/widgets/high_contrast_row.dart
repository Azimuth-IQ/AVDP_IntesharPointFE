import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/display_prefs.dart';
import 'package:inteshar/app/theme.dart';

/// Label + switch that turns the high-contrast theme on (UX-153).
///
/// Sits next to [LanguageSwitcherRow] wherever that appears — the About dialog
/// and drawer in the agent shell, and the POS account panel — because those are
/// the two "settings" surfaces the product has, and an operator looking for
/// "make this readable" looks where they found "change the language".
///
/// Deliberately worded as *what it does*, not as a mode name: "تباين عالي /
/// High contrast" with a one-line explanation, because the person who needs it
/// is standing in the sun squinting at a receipt, not browsing preferences.
///
/// The strings are bilingual literals rather than `.arb` keys, matching the
/// idiom already used for the nav labels in `app_scaffold.dart`.
class HighContrastRow extends ConsumerWidget {
  /// Show the explanatory second line. Off in tight slots (a dialog footer).
  final bool showHint;

  const HighContrastRow({super.key, this.showHint = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final on = ref.watch(highContrastProvider);
    return Row(
      children: [
        Icon(Icons.contrast_outlined, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: IntesharSpacing.sm2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr ? 'تباين عالي' : 'High contrast',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (showHint)
                Text(
                  isAr
                      ? 'أوضح تحت أشعة الشمس'
                      : 'Easier to read in sunlight',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Switch(
          value: on,
          onChanged: (v) => ref.read(highContrastProvider.notifier).set(v),
        ),
      ],
    );
  }
}
