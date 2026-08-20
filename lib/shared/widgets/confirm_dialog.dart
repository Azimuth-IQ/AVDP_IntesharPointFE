import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';

/// The app's one confirmation dialog (UX-129).
///
/// Before this there were 43 hand-rolled `AlertDialog`s and the confirm button
/// was red on some screens ("Delete agent", "Delete definition") and plain
/// brand-gold on others that were just as irreversible ("Delete slide",
/// "Deactivate", "Remove user", "Discard"). The CTA colour is the app's whole
/// "yes, do it" signal — when it is inconsistent it signals nothing, and the
/// operator learns to tap the coloured button on reflex.
///
/// So the colour is not the caller's choice: [destructive] picks it. Destructive
/// confirms are red-on-white with a red icon; everything else uses the standard
/// ink `FilledButton`. Cancel is always the plain text button and is always
/// what a barrier tap / back gesture resolves to.
///
/// Returns `true` only when the confirm button was pressed.
///
/// ```dart
/// if (!await showConfirm(context,
///     title: ar ? 'حذف الوكيل؟' : 'Delete agent?',
///     body:  ar ? 'لا يمكن التراجع.' : 'This cannot be undone.',
///     confirmLabel: ar ? 'حذف' : 'Delete',
///     destructive: true)) return;
/// ```
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmLabel,
  String? cancelLabel,
  IconData? icon,
  bool destructive = false,
  Key? confirmKey,
}) async {
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final accent = destructive ? cs.error : ctx.tones.brandOnSurface;
      return AlertDialog(
        icon: Icon(
          icon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline),
          color: accent,
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(body),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            key: const Key('confirm-dialog-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel ?? (ar ? 'إلغاء' : 'Cancel')),
          ),
          FilledButton(
            key: confirmKey ?? const Key('confirm-dialog-confirm'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? (ar ? 'تأكيد' : 'Confirm')),
          ),
        ],
      );
    },
  );
  return ok == true;
}
