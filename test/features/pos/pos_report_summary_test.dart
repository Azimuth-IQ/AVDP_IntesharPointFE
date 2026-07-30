import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/report_receipt.dart';
import 'package:inteshar/features/inventory/domain/print_operation.dart';
import 'package:inteshar/features/pos/domain/pos_report_summary.dart';

/// The POS التقارير screen listed cards with no totals and no way to put the
/// window on paper, while سستم التقارير!A1 requires every report to name the
/// shop, its owner and both agents, and A4 requires per-category card counts.
///
/// These assert the produced report, not the code that produces it: the text
/// artifact is decoded and read back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PrintOperation op({
    String name = 'Asiacell 5000',
    String sku = 'ASC-5000',
    double? price = 5000,
    bool printed = true,
  }) =>
      PrintOperation(
        id: 'x',
        receiptNo: 1,
        storeId: 's',
        storeName: 'saad',
        productId: 'p',
        serialNumber: '10317061784',
        sku: sku,
        productName: name,
        createdAt: '2026-07-30T14:00:00',
        soldPrice: price,
        printed: printed,
      );

  group('totals', () {
    test('counts cards, money, and unprinted separately', () {
      final s = PosReportSummary.from([
        op(),
        op(printed: false),
        op(name: 'Zain 10000', sku: 'ZN-10000', price: 10000),
      ]);
      expect(s.cards, 3);
      expect(s.total, 20000);
      expect(s.notPrinted, 1);
    });

    test('a sale with no recorded price counts as a card but not as money', () {
      // Otherwise a till reconciliation silently disagrees with the card count
      // and nothing on the report explains the gap.
      final s = PosReportSummary.from([op(), op(price: null)]);
      expect(s.cards, 2);
      expect(s.total, 5000);
      expect(s.unpriced, 1);
    });

    test('groups by category, busiest first (التقارير!A4)', () {
      final s = PosReportSummary.from([
        op(name: 'Zain 10000', sku: 'ZN', price: 10000),
        op(),
        op(),
      ]);
      expect(s.byCategory.first.category, 'Asiacell 5000');
      expect(s.byCategory.first.cards, 2);
      expect(s.byCategory.first.total, 10000);
      expect(s.byCategory.last.category, 'Zain 10000');
    });

    test('a nameless definition groups under its SKU instead of vanishing', () {
      final s = PosReportSummary.from([op(name: '  ', sku: 'ASC-5000')]);
      expect(s.byCategory.single.category, 'ASC-5000');
    });

    test('an empty window is a real zero, not a crash', () {
      final s = PosReportSummary.from([]);
      expect(s.cards, 0);
      expect(s.total, 0);
      expect(s.byCategory, isEmpty);
    });
  });

  group('the printed report', () {
    const identity = PosReportIdentity(
      shopName: 'محل سعد',
      ownerName: 'سعد عبد الله محمد',
      subAgentName: 'وكيل الرصافة',
      mainAgentName: 'وكيل بغداد',
    );

    String textOf(PosReportSummary s, {PosReportIdentity id = identity}) =>
        buildSalesReportText(
          identity: id,
          summary: s,
          fromDay: '2026-07-01',
          toDay: '2026-07-30',
          printedAt: DateTime(2026, 7, 30, 14, 6),
          ar: true,
        );

    test('carries every identity line the spec mandates (التقارير!A1)', () {
      final t = textOf(PosReportSummary.from([op()]));
      expect(t, contains('محل سعد'));
      expect(t, contains('سعد عبد الله محمد'));
      expect(t, contains('وكيل الرصافة'));
      expect(t, contains('وكيل بغداد'));
    });

    test('omits an identity line it could not resolve, rather than printing it blank', () {
      // A shop may be refused the entity reads that name its agents.
      final t = textOf(PosReportSummary.from([op()]),
          id: const PosReportIdentity(shopName: 'محل سعد'));
      expect(t, contains('محل سعد'));
      expect(t, isNot(contains('الوكيل الرئيسي')));
      expect(t, isNot(contains('صاحب النقطة')));
    });

    test('states the window and the totals', () {
      final t = textOf(PosReportSummary.from([op(), op(price: 10000)]));
      expect(t, contains('2026-07-01'));
      expect(t, contains('2026-07-30'));
      expect(t, contains('15,000'));
    });

    test('a partial window says so ON THE PAPER', () {
      // The print outlives the screen, so the caveat has to travel with it.
      final full = textOf(PosReportSummary.from([op()]));
      final part = textOf(PosReportSummary.from([op()], truncated: true));
      expect(full, isNot(contains('جزئي')));
      expect(part, contains('جزئي'));
    });

    test('English and Arabic differ — the report is really translated', () {
      final ar = buildSalesReportText(
        identity: identity,
        summary: PosReportSummary.from([op()]),
        fromDay: '2026-07-01',
        toDay: '2026-07-30',
        printedAt: DateTime(2026, 7, 30),
        ar: true,
      );
      final en = buildSalesReportText(
        identity: identity,
        summary: PosReportSummary.from([op()]),
        fromDay: '2026-07-01',
        toDay: '2026-07-30',
        printedAt: DateTime(2026, 7, 30),
        ar: false,
      );
      expect(ar, isNot(en));
      expect(en, contains('Sales report'));
      expect(RegExp(r'[؀-ۿ]').hasMatch(ar), isTrue);
    });
  });

  test('the report renders to real bytes with Arabic content', () async {
    // The voucher path threw on a single Arabic character for months. This
    // report is Arabic end to end, so it must be built, not merely composed.
    final job = await buildSalesReportPrintJob(
      identity: const PosReportIdentity(
        shopName: 'محل سعد',
        ownerName: 'سعد عبد الله محمد',
        mainAgentName: 'وكيل بغداد',
      ),
      summary: PosReportSummary.from([op(name: 'اسيا سيل 5000')]),
      fromDay: '2026-07-01',
      toDay: '2026-07-30',
      printedAt: DateTime(2026, 7, 30, 14, 6),
      ar: true,
    );
    expect(job.bytes, isNotEmpty);
    expect(job.hasText, isTrue, reason: 'intent printers need the text fallback');
  });
}
