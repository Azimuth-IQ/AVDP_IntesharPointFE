import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// Label + an ar/en segmented control.
///
/// B-096: this used to be private to `app_scaffold.dart`, which meant the POS —
/// a separate shell that never imports the agent scaffold — had NO way to change
/// the language at all; an operator was stuck on whatever the default was. It's
/// shared now so both shells can offer it.
class LanguageSwitcherRow extends ConsumerWidget {
  const LanguageSwitcherRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final locale = ref.watch(localeControllerProvider);
    return Row(
      children: [
        Icon(Icons.translate_outlined, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l.languageLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelSmall,
            ),
          ),
          segments: [
            ButtonSegment(value: 'ar', label: Text(l.languageArabic)),
            ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
          ],
          selected: {locale.languageCode},
          onSelectionChanged: (sel) {
            ref.read(localeControllerProvider.notifier).setLocale(Locale(sel.first));
          },
        ),
      ],
    );
  }
}

/// The name of the language a tap would switch TO, written in its own script —
/// so an Arabic UI shows "English" and vice-versa. Used for the one-tap toggle
/// in the agent sidebar footer, where a segmented control doesn't fit the row.
String otherLanguageLabel(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar' ? 'English' : 'العربية';
