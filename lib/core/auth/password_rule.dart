/// PROD-008: the one rule for a NEW sign-in password — at least 6 characters, with a capital
/// letter, a small letter, a number and a symbol (the client, 2026-11-19).
///
/// The backend's `Core/Helpers/PasswordPolicy.java` holds the same rule and is the copy that
/// counts; this one exists so the person sees what is missing while typing, before Save.
/// Keep the two in step. POS PINs (4 digits) are a separate credential and are not affected.
library;

/// One point of the rule, in the order it is shown.
enum PasswordNeed { length, upper, lower, digit, symbol }

class PasswordRule {
  PasswordRule._();

  static const int minLength = 6;

  static final _upper = RegExp(r'\p{Lu}', unicode: true);
  static final _lower = RegExp(r'\p{Ll}', unicode: true);
  static final _digit = RegExp(r'\p{Nd}', unicode: true);
  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _space = RegExp(r'\s');

  /// The points [value] already meets. Checked on the trimmed value, like the server.
  static Set<PasswordNeed> met(String? value) {
    final p = (value ?? '').trim();
    final out = <PasswordNeed>{};
    if (p.runes.length >= minLength) out.add(PasswordNeed.length);
    for (final r in p.runes) {
      final c = String.fromCharCode(r);
      if (_upper.hasMatch(c)) {
        out.add(PasswordNeed.upper);
      } else if (_lower.hasMatch(c)) {
        out.add(PasswordNeed.lower);
      } else if (_digit.hasMatch(c)) {
        out.add(PasswordNeed.digit);
      } else if (!_letter.hasMatch(c) && !_space.hasMatch(c)) {
        out.add(PasswordNeed.symbol);
      }
    }
    return out;
  }

  /// The points [value] still misses, in the rule's order; empty when it is acceptable.
  static List<PasswordNeed> missing(String? value) {
    final ok = met(value);
    return PasswordNeed.values.where((n) => !ok.contains(n)).toList();
  }

  static bool isStrong(String? value) => missing(value).isEmpty;

  /// The line shown for one point of the rule.
  static String label(PasswordNeed n, {required bool ar}) => switch (n) {
        PasswordNeed.length => ar ? '6 أحرف على الأقل' : 'At least 6 characters',
        PasswordNeed.upper => ar ? 'حرف إنجليزي كبير (A-Z)' : 'A capital letter (A-Z)',
        PasswordNeed.lower => ar ? 'حرف إنجليزي صغير (a-z)' : 'A small letter (a-z)',
        PasswordNeed.digit => ar ? 'رقم (0-9)' : 'A number (0-9)',
        PasswordNeed.symbol => ar ? 'رمز مثل @ # ! \$ %' : r'A symbol such as @ # ! $ %',
      };

  /// The heading above the checklist.
  static String heading({required bool ar}) =>
      ar ? 'كلمة المرور يجب أن تحتوي على:' : 'The password must have:';

  /// For a form field or a save check: null when [value] meets the rule, otherwise what is
  /// still missing, in one line.
  static String? validate(String? value, {required bool ar}) {
    final miss = missing(value);
    if (miss.isEmpty) return null;
    final parts = miss.map((n) => label(n, ar: ar));
    return ar
        ? 'كلمة المرور ضعيفة — ينقصها: ${parts.join('، ')}'
        : 'Weak password — missing: ${parts.join(', ')}';
  }
}
