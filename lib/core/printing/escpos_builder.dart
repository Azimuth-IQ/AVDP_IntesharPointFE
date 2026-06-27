import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';

String _fmtTs(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Builds a 58mm voucher receipt driven by the SKU's [VoucherTemplate] — the
/// same template HQ designs in the Voucher Templates screen. Field visibility,
/// header/footer, redeem instructions and the QR payload (prefix + PIN/serial +
/// suffix, e.g. `*133*PIN#`) all come from the template, so what HQ designs is
/// exactly what the Store prints.
Future<List<int>> buildVoucherReceipt({
  required VoucherTemplate template,
  required String companyName,
  required String shopName,
  required String posLabel,
  required String operatorPhone,
  required String productName,
  required String price,
  required String serial,
  required String pin,
  required DateTime timestamp,
}) async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final out = <int>[];

  final header = template.headerText.trim().isNotEmpty
      ? template.headerText.trim()
      : companyName;
  out.addAll(g.text(header,
      styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2)));
  out.addAll(g.text(shopName, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.text(posLabel, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.hr());

  if (template.showProductName) {
    out.addAll(g.text(productName,
        styles: const PosStyles(
            align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  }
  if (template.showPrice) {
    out.addAll(g.text(price,
        styles: const PosStyles(align: PosAlign.center, bold: true)));
  }
  if (template.showProductName || template.showPrice) out.addAll(g.feed(1));

  if (template.showSerial) {
    out.addAll(g.text('Serial: $serial',
        styles: const PosStyles(align: PosAlign.center)));
  }
  if (template.showPin) {
    out.addAll(g.text('PIN: $pin',
        styles: const PosStyles(
            align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  }

  if (template.qrEnabled) {
    final payload = template.qrPayload(pin: pin, serial: serial);
    out.addAll(g.feed(1));
    out.addAll(g.qrcode(payload));
    final caption = template.redeemInstructions.trim().isNotEmpty
        ? template.redeemInstructions.trim()
        : payload;
    out.addAll(g.text(caption, styles: const PosStyles(align: PosAlign.center)));
  } else if (template.redeemInstructions.trim().isNotEmpty) {
    out.addAll(g.feed(1));
    out.addAll(g.text(template.redeemInstructions.trim(),
        styles: const PosStyles(align: PosAlign.center)));
  }

  out.addAll(g.hr());
  out.addAll(
      g.text(_fmtTs(timestamp), styles: const PosStyles(align: PosAlign.center)));
  if (operatorPhone.isNotEmpty) {
    out.addAll(g.text('Op: $operatorPhone',
        styles: const PosStyles(align: PosAlign.center)));
  }
  if (template.footerText.trim().isNotEmpty) {
    out.addAll(g.feed(1));
    out.addAll(g.text(template.footerText.trim(),
        styles: const PosStyles(align: PosAlign.center)));
  }
  out.addAll(g.feed(2));
  out.addAll(g.cut());
  return out;
}

Future<List<int>> buildTestReceipt() async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final out = <int>[];
  out.addAll(g.text('Inteshar Platform',
      styles: const PosStyles(
          align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  out.addAll(g.text('Printer OK', styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.feed(2));
  out.addAll(g.cut());
  return out;
}
