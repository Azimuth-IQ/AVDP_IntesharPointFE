import 'package:intl/intl.dart';

class Formatters {
  static String iqd(dynamic amount, {bool arabicNumerals = false}) {
    final n = int.tryParse(amount.toString()) ?? 0;
    final formatted = NumberFormat('#,###').format(n);
    return '$formatted IQD';
  }

  static String date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String time(DateTime d) => DateFormat('HH:mm').format(d);
  static String dateTime(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d);
}
