import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

class Formatters {
  /// Language the currency UNIT is written in — `'ar'` → `د.ع`, anything else
  /// → `IQD` (UX-57).
  ///
  /// [iqd] is a static with ~53 call sites and no `BuildContext`, so the app
  /// pushes the locale here instead (`IntesharApp.build`). It is a plain
  /// assignment of the value the app is already rebuilding with, so there is no
  /// frame where the two disagree. Where a context IS in hand — and especially
  /// on the printed receipt, which must follow the language it is printed in —
  /// prefer [iqdOf].
  static String languageCode = 'ar';

  /// The Iraqi dinar as Arabic readers write it. Latin "IQD" is an accounting
  /// code; this is the unit on every price tag, till receipt and banknote here.
  static const String unitAr = 'د.ع';
  static const String unitEn = 'IQD';

  static String currencyUnit([String? lang]) =>
      (lang ?? languageCode) == 'ar' ? unitAr : unitEn;

  /// An amount with its currency unit, in the app's language.
  ///
  /// Was hardcoded Latin `"IQD"` on every price, the balance hero, every total
  /// and the thermal receipt the customer walks out with — in an Arabic-first
  /// product. The old `arabicNumerals` flag was declared, never read and had no
  /// caller; it is gone rather than left as a lie (Iraqi POS receipts use
  /// Western digits, and the thermal printer cannot raster Arabic-Indic ones
  /// reliably anyway).
  static String iqd(dynamic amount, {String? languageCode}) =>
      '${money(amount)} ${currencyUnit(languageCode)}';

  /// [iqd] resolved against the widget tree's locale instead of the global —
  /// use it whenever a context is available.
  static String iqdOf(BuildContext context, dynamic amount) =>
      iqd(amount, languageCode: Localizations.localeOf(context).languageCode);

  /// Thousands-separated number WITHOUT a currency suffix — for money labels that supply
  /// their own currency word/context (e.g. an "IQD" suffixText, or "الرصيد: 15,000 د.ع").
  /// Also correct for large plain counts.
  ///
  /// Amounts arrive from the API as doubles (e.g. `15000.0`), and
  /// `int.tryParse('15000.0')` returns null — that once rendered every
  /// double-typed price as `0 IQD`. Round through `num`, never `int.parse`.
  static String money(dynamic amount) {
    final n = amount is num
        ? amount.round()
        : (num.tryParse(amount.toString())?.round() ?? 0);
    return NumberFormat('#,###').format(n);
  }

  static String date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String time(DateTime d) => DateFormat('HH:mm').format(d);
  static String dateTime(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d);
}

/// B-093: groups digits with thousand separators AS THE OPERATOR TYPES, so a money
/// field reads `500,000` instead of `500000` — the difference between 50k and 500k
/// is otherwise a digit-counting exercise on a live money entry.
///
/// Strips any non-digit first, so it also sanitises paste. Always read the value
/// back with [parseAmount] — the raw text contains separators and `num.parse`
/// would throw on it.
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final grouped = _group(digits);
    // Keep the caret at the end — these are short, append-style money entries.
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return b.toString();
  }
}

/// Reads a possibly-grouped amount field back to a number (`"500,000"` → 500000).
/// Returns null when there is no digit at all.
num? parseAmount(String? text) {
  if (text == null) return null;
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return num.tryParse(digits);
}
