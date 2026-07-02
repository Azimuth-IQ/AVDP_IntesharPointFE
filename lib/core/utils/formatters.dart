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

  static String date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String time(DateTime d) => DateFormat('HH:mm').format(d);
  static String dateTime(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d);
}
