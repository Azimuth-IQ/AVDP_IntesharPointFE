import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

Future<List<int>> buildVoucherReceipt({
  required String companyName,
  required String shopName,
  required String posLabel,
  required String operatorPhone,
  required String denomination,
  required String serial,
  required String pin,
  required DateTime timestamp,
}) async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final out = <int>[];

  out.addAll(g.text(companyName,
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
  out.addAll(g.text(shopName, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.text(posLabel, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.hr());
  out.addAll(g.text(denomination,
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  out.addAll(g.feed(1));
  out.addAll(g.text('Serial: $serial', styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.text('PIN:    $pin',
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  out.addAll(g.feed(1));
  out.addAll(g.qrcode(pin));
  out.addAll(g.hr());
  out.addAll(g.text(
    '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} '
    '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
    styles: const PosStyles(align: PosAlign.center),
  ));
  out.addAll(g.text('Op: $operatorPhone', styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.feed(2));
  out.addAll(g.cut());
  return out;
}

Future<List<int>> buildTestReceipt() async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final out = <int>[];
  out.addAll(g.text('Inteshar Point',
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  out.addAll(g.text('Printer OK', styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.feed(2));
  out.addAll(g.cut());
  return out;
}
