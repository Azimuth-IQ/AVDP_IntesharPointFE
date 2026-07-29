import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:inteshar/core/printing/print_job.dart';
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
  required String headerFallback,
  required String shopName,
  required String posLabel,
  required String operatorPhone,
  required String productName,
  required String price,
  required String serial,
  required String pin,
  required DateTime timestamp,
  img.Image? agentLogo,
  img.Image? companyLogo,
  String? companyName,
  String? categoryName,
  String? expiry,
  int? receiptNo,
}) async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final out = <int>[];

  // Main-agent logo at the very top (white-label branding).
  if (template.showAgentLogo && agentLogo != null) {
    out.addAll(g.imageRaster(agentLogo, align: PosAlign.center));
    out.addAll(g.feed(1));
  }

  final header = template.headerText.trim().isNotEmpty
      ? template.headerText.trim()
      : headerFallback;
  out.addAll(
    g.text(
      header,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ),
  );
  out.addAll(g.text(shopName, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.text(posLabel, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.hr());

  // Company logo (e.g. Asiacell) above the product/code.
  if (template.showCompanyLogo && companyLogo != null) {
    out.addAll(g.imageRaster(companyLogo, align: PosAlign.center));
    out.addAll(g.feed(1));
  }

  // Telecom company name (e.g. Asiacell) then the category name beneath it,
  // each gated by its template flag (and only when a value is present).
  if (template.showCompanyName &&
      companyName != null &&
      companyName.trim().isNotEmpty) {
    out.addAll(
      g.text(
        companyName.trim(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
  }
  if (template.showCategoryName &&
      categoryName != null &&
      categoryName.trim().isNotEmpty) {
    out.addAll(
      g.text(
        categoryName.trim(),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
  }

  if (template.showProductName) {
    out.addAll(
      g.text(
        productName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
  }
  if (template.showPrice) {
    out.addAll(
      g.text(
        price,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
  }
  if (template.showProductName || template.showPrice) out.addAll(g.feed(1));

  if (template.showSerial) {
    out.addAll(
      g.text(
        'Serial: $serial',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
  }
  if (template.showPin) {
    out.addAll(
      g.text(
        'PIN: $pin',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
  }

  if (template.qrEnabled) {
    final payload = template.qrPayload(pin: pin, serial: serial);
    out.addAll(g.feed(1));
    out.addAll(g.qrcode(payload));
    final caption = template.redeemInstructions.trim().isNotEmpty
        ? template.redeemInstructions.trim()
        : payload;
    out.addAll(
      g.text(caption, styles: const PosStyles(align: PosAlign.center)),
    );
  } else if (template.redeemInstructions.trim().isNotEmpty) {
    out.addAll(g.feed(1));
    out.addAll(
      g.text(
        template.redeemInstructions.trim(),
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
  }

  // Expiry below the code (per the client's note).
  if (template.showExpiry && expiry != null && expiry.trim().isNotEmpty) {
    out.addAll(g.feed(1));
    out.addAll(
      g.text(
        'Expiry: ${expiry.trim()}',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
  }

  out.addAll(g.hr());
  // Operation reference: per-store receipt number + the voucher serial.
  if (receiptNo != null && receiptNo > 0) {
    out.addAll(
      g.text(
        'Receipt #$receiptNo',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
  }
  out.addAll(
    g.text('Ref: $serial', styles: const PosStyles(align: PosAlign.center)),
  );
  out.addAll(
    g.text(_fmtTs(timestamp), styles: const PosStyles(align: PosAlign.center)),
  );
  if (operatorPhone.isNotEmpty) {
    out.addAll(
      g.text(
        'Op: $operatorPhone',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
  }
  if (template.footerText.trim().isNotEmpty) {
    out.addAll(g.feed(1));
    out.addAll(
      g.text(
        template.footerText.trim(),
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
  }
  out.addAll(g.feed(2));
  out.addAll(g.cut());
  return out;
}

/// Plain-text version of the voucher receipt for intent-based printers (Rovo/BLD) that
/// accept EXTRA_TEXT rather than ESC/POS bytes. Mirrors [buildVoucherReceipt]'s content and
/// template toggles; logos/QR can't render as text, so the QR payload + redeem instructions
/// are written out (the PIN — what the customer actually needs — is always shown).
String buildVoucherReceiptText({
  required VoucherTemplate template,
  required String headerFallback,
  required String shopName,
  required String posLabel,
  required String operatorPhone,
  required String productName,
  required String price,
  required String serial,
  required String pin,
  required DateTime timestamp,
  String? companyName,
  String? categoryName,
  String? expiry,
  int? receiptNo,
}) {
  final b = StringBuffer();
  void line([String s = '']) => b.writeln(s);
  const sep = '--------------------------------';

  line(
    template.headerText.trim().isNotEmpty
        ? template.headerText.trim()
        : headerFallback,
  );
  if (shopName.isNotEmpty) line(shopName);
  if (posLabel.isNotEmpty) line(posLabel);
  line(sep);

  if (template.showCompanyName && (companyName ?? '').trim().isNotEmpty) {
    line(companyName!.trim());
  }
  if (template.showCategoryName && (categoryName ?? '').trim().isNotEmpty) {
    line(categoryName!.trim());
  }
  if (template.showProductName) line(productName);
  if (template.showPrice) line(price);
  if (template.showProductName || template.showPrice) line();

  if (template.showSerial) line('Serial: $serial');
  if (template.showPin) line('PIN: $pin');

  if (template.qrEnabled) {
    if (template.redeemInstructions.trim().isNotEmpty) {
      line(template.redeemInstructions.trim());
    }
    line(template.qrPayload(pin: pin, serial: serial));
  } else if (template.redeemInstructions.trim().isNotEmpty) {
    line(template.redeemInstructions.trim());
  }

  if (template.showExpiry && (expiry ?? '').trim().isNotEmpty) {
    line('Expiry: ${expiry!.trim()}');
  }

  line(sep);
  if (receiptNo != null && receiptNo > 0) line('Receipt #$receiptNo');
  line('Ref: $serial');
  line(_fmtTs(timestamp));
  if (operatorPhone.isNotEmpty) line('Op: $operatorPhone');
  if (template.footerText.trim().isNotEmpty) {
    line();
    line(template.footerText.trim());
  }
  return b.toString();
}

/// One voucher receipt, ready for ANY transport.
///
/// CR-06: the ESC/POS bytes are the receipt; the text is a fallback only the
/// lossy vendor-intent path can use. Building both here is what lets every
/// caller stop asking "is this a Rovo?" — the transport picks the field it can
/// handle, and on every raw transport the bytes below are what reaches paper.
Future<PrintJob> buildVoucherPrintJob({
  required VoucherTemplate template,
  required String headerFallback,
  required String shopName,
  required String posLabel,
  required String operatorPhone,
  required String productName,
  required String price,
  required String serial,
  required String pin,
  required DateTime timestamp,
  img.Image? agentLogo,
  img.Image? companyLogo,
  String? companyName,
  String? categoryName,
  String? expiry,
  int? receiptNo,
}) async {
  final bytes = await buildVoucherReceipt(
    template: template,
    headerFallback: headerFallback,
    shopName: shopName,
    posLabel: posLabel,
    operatorPhone: operatorPhone,
    productName: productName,
    price: price,
    serial: serial,
    pin: pin,
    timestamp: timestamp,
    agentLogo: agentLogo,
    companyLogo: companyLogo,
    companyName: companyName,
    categoryName: categoryName,
    expiry: expiry,
    receiptNo: receiptNo,
  );
  final text = buildVoucherReceiptText(
    template: template,
    headerFallback: headerFallback,
    shopName: shopName,
    posLabel: posLabel,
    operatorPhone: operatorPhone,
    productName: productName,
    price: price,
    serial: serial,
    pin: pin,
    timestamp: timestamp,
    companyName: companyName,
    categoryName: categoryName,
    expiry: expiry,
    receiptNo: receiptNo,
  );
  return PrintJob(bytes: bytes, text: text);
}

/// The test receipt, for every transport.
Future<PrintJob> buildTestPrintJob() async => PrintJob(
  bytes: await buildTestReceipt(),
  text: 'Point of Sale\nPrinter OK\n',
);

Future<List<int>> buildTestReceipt() async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final out = <int>[];
  out.addAll(
    g.text(
      'Point of Sale',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    ),
  );
  out.addAll(
    g.text('Printer OK', styles: const PosStyles(align: PosAlign.center)),
  );
  out.addAll(g.feed(2));
  out.addAll(g.cut());
  return out;
}
