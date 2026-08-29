import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';

/// Asks for the operator's six-digit authenticator code before an irreversible
/// delete, and explains what is about to disappear.
///
/// One implementation on purpose: the hierarchy delete and the clear-out sheet
/// both use it, and a second copy is how one of them ends up without the prompt.
/// Returns the trimmed code, or null when the operator backs out.
Future<String?> showConfirmCodeDialog(
  BuildContext context, {
  required String title,
  required String warning,
  /// Overrides the confirm button's wording. Defaults to "Delete" because that is
  /// what this prompt guards most often; a restore is not a deletion and must not
  /// say so.
  String? confirmLabel,
  /// Restores are not destructive, so they do not get the alarm colouring.
  bool destructive = true,
}) {
  final isAr = Localizations.localeOf(context).languageCode == 'ar';
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.gpp_maybe_outlined,
            color: destructive ? cs.error : cs.primary),
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(warning, style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: IntesharSpacing.lg),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: isAr ? 'رمز المصادقة' : 'Authentication code',
                  helperText: isAr
                      ? 'من تطبيق المصادقة الخاص بك'
                      : 'From your authenticator app',
                  counterText: '',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) {
                    return isAr ? 'أدخل الرمز' : 'Enter the code';
                  }
                  if (t.length != 6 || int.tryParse(t) == null) {
                    return isAr ? 'الرمز 6 أرقام' : 'The code is 6 digits';
                  }
                  return null;
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(ctx, controller.text.trim());
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: destructive ? cs.error : cs.primary),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text(confirmLabel ?? (isAr ? 'حذف' : 'Delete')),
          ),
        ],
      );
    },
  );
}
