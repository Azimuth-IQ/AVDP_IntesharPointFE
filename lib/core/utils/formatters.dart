import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class Formatters {
  static String iqd(dynamic amount, {bool arabicNumerals = false}) {
    // Prices/amounts arrive from the API as doubles (e.g. 15000.0). int.tryParse('15000.0')
    // returns null → don't do that (it silently rendered every double price as "0 IQD").
    final n = amount is num
        ? amount.round()
        : (num.tryParse(amount.toString())?.round() ?? 0);
    final formatted = NumberFormat('#,###').format(n);
    return '$formatted IQD';
  }

  /// Thousands-separated number WITHOUT a currency suffix — for money labels that supply
  /// their own currency word/context (e.g. an "IQD" suffixText, or "الرصيد: 15,000 د.ع").
  /// Also correct for large plain counts. Handles doubles ("15000.0") like [iqd].
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
