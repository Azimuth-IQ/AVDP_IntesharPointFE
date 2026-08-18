import 'package:flutter/material.dart';

/// Confirmations for the operator-credential resets, in ONE place because the
/// same two actions are offered from two screens (the shop admin page and the
/// store view) and a confirmation added to only one of them is the bug this
/// file exists to prevent.
///
/// Both resets take effect the instant they are confirmed and land on someone
/// who is usually mid-shift, so each prompt says what stops working and how the
/// operator gets back in — the recovery is the part the admin has to act on.
///
/// Returns true when the operator confirmed.
Future<bool> confirmResetPin(BuildContext context, {String? posName}) async {
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  return _ask(
    context,
    icon: Icons.password_outlined,
    title: ar ? 'إصدار رمز دخول جديد؟' : 'Issue a new PIN?',
    body: ar
        ? 'سيتوقف رمز الدخول الحالي فوراً${posName == null ? '' : ' لـ $posName'}، '
            'ولن يتمكن الكاشير من البيع حتى تُبلغه بالرمز الجديد. '
            'سيظهر الرمز الجديد بعد التأكيد.'
        : 'The current PIN stops working immediately${posName == null ? '' : ' for $posName'}, '
            'and the cashier cannot sell until you read them the new one. '
            'The new PIN is shown after you confirm.',
    confirm: ar ? 'إصدار رمز جديد' : 'Issue new PIN',
  );
}

Future<bool> confirmResetTotp(BuildContext context, {String? posName}) async {
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  return _ask(
    context,
    icon: Icons.shield_outlined,
    title: ar ? 'إعادة تعيين المصادقة الثنائية؟' : 'Reset two-factor?',
    body: ar
        ? 'سيفقد${posName == null ? '' : ' $posName'} إمكانية الدخول حتى يسجّل '
            'تطبيق المصادقة من جديد. يظهر رمز التسجيل مرة واحدة فقط عند دخوله التالي.'
        : '${posName ?? 'They'} cannot sign in until they enrol an authenticator '
            'app again. The enrolment code is shown once, on their next sign-in.',
    confirm: ar ? 'إعادة التعيين' : 'Reset',
  );
}

Future<bool> _ask(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String confirm,
}) async {
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(icon, color: cs.primary),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-operator-reset'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm),
          ),
        ],
      );
    },
  );
  return ok == true;
}
