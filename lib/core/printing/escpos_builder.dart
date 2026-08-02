import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/painting.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/receipt_raster.dart';
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
  bool cutAtEnd = false,
  // Field labels, passed in from the caller's AppLocalizations so the printed
  // receipt uses the SAME wording as the voucher on screen (الرقم السري, not a
  // hardcoded "PIN:"). English defaults keep non-localized callers working.
  String labelSerial = 'Serial',
  String labelPin = 'PIN',
  String labelExpiry = 'Expiry',
  String labelReceiptNo = 'Receipt #',
}) async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final width = PaperSize.mm58.width;

  // The receipt is laid out as PIXELS, not ESC/POS text. `Generator.text()`
  // encodes Latin-1, so one Arabic character threw "Contains invalid
  // characters" and the receipt could not be built at all — every real Iraqi
  // template hit this. Rendering through Flutter's text engine also fixes
  // Arabic shaping and RTL, which no ESC/POS code page does for us. See
  // receipt_raster.dart.
  final blocks = <ReceiptBlock>[];

  if (template.showAgentLogo && agentLogo != null) {
    blocks.add(ImageBlock(agentLogo));
  }

  final header = template.headerText.trim().isNotEmpty
      ? template.headerText.trim()
      : headerFallback;
  blocks.add(TextBlock(header, fontSize: 36, weight: FontWeight.w800, padBottom: 5));
  // The callers pass the entity name as BOTH the header fallback and the shop
  // name, so it printed twice. Only add it when it says something new.
  if (shopName.trim().isNotEmpty && shopName.trim() != header.trim()) {
    blocks.add(TextBlock(shopName, fontSize: 26));
  }
  blocks.add(RuleBlock());

  if (template.showCompanyLogo && companyLogo != null) {
    blocks.add(ImageBlock(companyLogo));
  }
  if (template.showCompanyName && (companyName ?? '').trim().isNotEmpty) {
    blocks.add(
      TextBlock(companyName!.trim(), fontSize: 30, weight: FontWeight.w700, padBottom: 4),
    );
  }
  // categoryName defaults to the product name at every call site, so printing
  // both repeated the same line twice on a 48mm-wide receipt.
  if (template.showCategoryName &&
      (categoryName ?? '').trim().isNotEmpty &&
      categoryName!.trim() != productName.trim()) {
    blocks.add(
      TextBlock(categoryName.trim(), fontSize: 26, weight: FontWeight.w700),
    );
  }
  if (template.showProductName) {
    blocks.add(TextBlock(productName, fontSize: 34, weight: FontWeight.w700, padBottom: 4));
  }
  if (template.showPrice) {
    blocks.add(TextBlock(price, fontSize: 30, weight: FontWeight.w700));
  }
  if (template.showProductName || template.showPrice) blocks.add(GapBlock(8));

  // Detail lines align to their own reading direction: TextAlign.start resolves
  // to the RIGHT under RTL and the left under LTR, so an Arabic receipt no longer
  // reads left-aligned. Headline blocks stay centred — that is conventional on a
  // receipt in either language, and centring is direction-neutral anyway.
  if (template.showSerial) {
    blocks.add(TextBlock('$labelSerial: $serial',
        fontSize: 26, padBottom: 5, align: TextAlign.start));
  }
  if (template.showPin) {
    // The one field the customer actually needs, and the one they key into a
    // phone: biggest thing on the paper, spaced like the on-screen voucher.
    //
    // It must NEVER wrap. A PIN broken across two lines gets read back wrong —
    // half of it keyed in, or the wrap taken for a space or a dash. PIN length
    // varies by operator and denomination, so 46px is the ceiling and the block
    // shrinks only as far as a longer code actually requires.
    blocks.add(
      LabelValueBlock(
        labelPin,
        pin,
        labelSize: 24,
        valueSize: 46,
        valueWeight: FontWeight.w800,
        valueSpacing: 2,
        padBottom: 10,
        singleLineValue: true,
        minValueSize: 18,
      ),
    );
  }

  if (template.qrEnabled) {
    final payload = template.qrPayload(pin: pin, serial: serial);
    blocks.add(GapBlock(8));
    blocks.add(QrBlock(payload, size: 170));
    final caption = template.redeemInstructions.trim().isNotEmpty
        ? template.redeemInstructions.trim()
        : payload;
    blocks.add(TextBlock(caption, fontSize: 24, padBottom: 5));
  } else if (template.redeemInstructions.trim().isNotEmpty) {
    blocks.add(GapBlock(8));
    blocks.add(TextBlock(template.redeemInstructions.trim(), fontSize: 24, padBottom: 5));
  }

  if (template.showExpiry && (expiry ?? '').trim().isNotEmpty) {
    blocks.add(GapBlock(8));
    blocks.add(
      TextBlock('$labelExpiry: ${expiry!.trim()}',
          fontSize: 24, padBottom: 4, align: TextAlign.start),
    );
  }

  blocks.add(RuleBlock());
  if (receiptNo != null && receiptNo > 0) {
    blocks.add(
      TextBlock('$labelReceiptNo: $receiptNo',
          fontSize: 24, padBottom: 4, align: TextAlign.start),
    );
  }
  blocks.add(TextBlock(_fmtTs(timestamp), fontSize: 20));
  if (template.footerText.trim().isNotEmpty) {
    blocks.add(GapBlock(8));
    blocks.add(TextBlock(template.footerText.trim(), fontSize: 24));
  }

  // Logos must be decoded into GPU images before layout can measure them.
  for (final b in blocks) {
    if (b is ImageBlock) await b.prepare();
  }

  final raster = await renderReceiptRaster(width: width, blocks: blocks);

  final out = <int>[];
  out.addAll(g.imageRaster(raster));
  // Paper handling, NOT content. `Generator.cut()` emits FIVE blank lines plus a
  // full-cut command, and the built-in heads in this fleet (Sunmi, Centerm/Rovo)
  // have no cutter — their firmware treats a cut as "advance to the tear-off
  // position", which added several centimetres of blank paper between receipts.
  // Feed just enough to clear the tear bar. A cutter-equipped model can opt in
  // via [cutAtEnd] rather than every device paying for it.
  out.addAll(g.feed(2));
  if (cutAtEnd) out.addAll(g.cut());
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
  String labelSerial = 'Serial',
  String labelPin = 'PIN',
  String labelExpiry = 'Expiry',
  String labelReceiptNo = 'Receipt #',
}) async {
  final bytes = await buildVoucherReceipt(
    template: template,
    headerFallback: headerFallback,
    shopName: shopName,
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
    labelSerial: labelSerial,
    labelPin: labelPin,
    labelExpiry: labelExpiry,
    labelReceiptNo: labelReceiptNo,
  );
  final text = buildVoucherReceiptText(
    template: template,
    headerFallback: headerFallback,
    shopName: shopName,
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
Future<PrintJob> buildTestPrintJob({bool cutAtEnd = false}) async => PrintJob(
  bytes: await buildTestReceipt(cutAtEnd: cutAtEnd),
  text: 'Point of Sale\nPrinter OK\n',
);

Future<List<int>> buildTestReceipt({bool cutAtEnd = false}) async {
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
  // Same cutterless-head reasoning as the voucher receipt above — and it matters
  // more here, because this is the slip you print repeatedly while triaging an
  // unknown printer. A cut on a cutterless head spends a receipt's worth of
  // paper per probe.
  out.addAll(g.feed(2));
  if (cutAtEnd) out.addAll(g.cut());
  return out;
}
