import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/receipt_raster.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';

/// The bug this file exists for: `Generator.text()` encodes **Latin-1**, so a
/// single Arabic character threw
/// `Invalid argument (string): Contains invalid characters.: "انتشار"`
/// and the receipt could not be BUILT — no transport was even reached. Every
/// real Iraqi template hit it, on every printer. It shipped unnoticed because
/// the only automated print coverage used ASCII, and the one device that appeared
/// to work (Rovo) was on the vendor-intent path, which sends a Dart String and
/// never touches the encoder.
///
/// So: assert on the REAL content, not a Latin-1-safe stand-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int> buildBytes({
    required String header,
    required String product,
    required String company,
    required String redeem,
    bool qr = true,
  }) async {
    final job = await buildVoucherPrintJob(
      template: VoucherTemplate(qrEnabled: qr, redeemInstructions: redeem),
      headerFallback: header,
      shopName: 'saad',
      posLabel: 'Counter 1',
      operatorPhone: '07701111113',
      productName: product,
      price: '5000',
      serial: '10317061784',
      pin: '000817837155530',
      timestamp: DateTime(2026, 7, 30, 14, 6),
      companyName: company,
      categoryName: product,
      expiry: '2028-06-30',
      receiptNo: 42,
    );
    return job.bytes.length;
  }

  test('an ARABIC voucher receipt builds — the exact content that threw', () async {
    final len = await buildBytes(
      header: 'انتشار',
      product: 'اسيا سيل 5000',
      company: 'اسيا سيل',
      redeem: 'لغرض التعبئة اتصل على 333',
    );
    expect(len, greaterThan(0));
  });

  test('a mixed Arabic + Latin + digits receipt builds', () async {
    // Bidi runs are where naive encoders and naive layouts both fall over.
    final len = await buildBytes(
      header: 'Inteshar انتشار',
      product: 'Asiacell اسيا سيل 5000 IQD',
      company: 'Asiacell / اسيا سيل',
      redeem: 'اتصل على *133*PIN# للتعبئة',
    );
    expect(len, greaterThan(0));
  });

  test('an ASCII receipt still builds, so nothing regressed for English', () async {
    final len = await buildBytes(
      header: 'Inteshar',
      product: 'Asiacell 5000',
      company: 'Asiacell',
      redeem: 'Dial *133*PIN# to top up',
    );
    expect(len, greaterThan(0));
  });

  test('a receipt with no QR still builds', () async {
    final len = await buildBytes(
      header: 'انتشار',
      product: 'اسيا سيل 5000',
      company: 'اسيا سيل',
      redeem: 'لغرض التعبئة اتصل على 333',
      qr: false,
    );
    expect(len, greaterThan(0));
  });

  test('the test receipt stays ASCII — it is the cheap transport check', () async {
    // Deliberately NOT rasterized: it must stay small and dependency-free so a
    // "does this printer respond at all" probe is meaningful.
    final job = await buildTestPrintJob();
    expect(job.bytes.length, greaterThan(0));
    expect(job.bytes.length, lessThan(2000),
        reason: 'a raster test page would hide transport-level problems');
  });

  group('Arabic detection drives the paragraph direction', () {
    test('recognises Arabic, including presentation forms', () {
      for (final s in ['انتشار', 'اسيا سيل 5000', 'PIN: ١٢٣', 'ﻻ']) {
        expect(containsArabic(s), isTrue, reason: s);
      }
    });

    test('leaves Latin text alone', () {
      for (final s in ['Asiacell 5000', 'PIN: 12345', '*133*PIN#', '']) {
        expect(containsArabic(s), isFalse, reason: s);
      }
    });
  });

  /// A raster receipt is priced in paper. The first version ran to 95mm per
  /// voucher and, with `Generator.cut()` adding five blank lines plus a full-cut
  /// that cutterless heads honour as "advance to the tear-off position", shops
  /// saw close to a blank voucher's worth of paper between receipts.
  group('paper length', () {
    /// Millimetres of 58mm paper the byte stream implies, at 203 dpi.
    double mmFor(int bytes) => (bytes / (PaperSize.mm58.width / 8)) / 203 * 25.4;

    test('a full Arabic voucher fits a sane length of paper', () async {
      final len = await buildBytes(
        header: 'انتشار',
        product: 'اسيا سيل 5000',
        company: 'اسيا سيل',
        redeem: 'لغرض التعبئة اتصل على 333',
      );
      // Deliberately loose: type big enough to read at arm's length costs paper,
      // and the first trim went so far the customer called it unreadable. This
      // guards runaway layout, not thriftiness.
      expect(mmFor(len), lessThan(150),
          reason: 'runaway layout burns the shop\'s paper roll');
      expect(mmFor(len), greaterThan(30),
          reason: 'suspiciously short — content is probably missing');
    });

    test('no cut command by default — these heads have no cutter', () async {
      final job = await buildVoucherPrintJob(
        template: VoucherTemplate(),
        headerFallback: 'Inteshar', shopName: 'saad', posLabel: 'Counter 1',
        operatorPhone: '07701111113', productName: 'Asiacell 5000', price: '5000',
        serial: 'SN1', pin: 'PIN1', timestamp: DateTime(2026, 7, 30),
      );
      expect(_containsGsV(job.bytes), isFalse);
    });

    test('a cutter-equipped printer can still opt in', () async {
      final bytes = await buildVoucherReceipt(
        template: VoucherTemplate(),
        headerFallback: 'Inteshar', shopName: 'saad', posLabel: 'Counter 1',
        operatorPhone: '07701111113', productName: 'Asiacell 5000', price: '5000',
        serial: 'SN1', pin: 'PIN1', timestamp: DateTime(2026, 7, 30),
        cutAtEnd: true,
      );
      expect(_containsGsV(bytes), isTrue);
    });
  });
}

/// GS V — the ESC/POS cut command.
bool _containsGsV(List<int> bytes) {
  for (var i = 0; i < bytes.length - 1; i++) {
    if (bytes[i] == 0x1D && bytes[i + 1] == 0x56) return true;
  }
  return false;
}
