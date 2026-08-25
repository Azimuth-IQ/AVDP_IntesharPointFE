import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/report_receipt.dart';
import 'package:inteshar/features/pos/domain/pos_report_summary.dart';

/// The POS التقارير screen listed cards with no totals and no way to put the
/// window on paper, while سستم التقارير!A1 requires every report to name the
/// shop, its owner and both agents, and A4 requires per-category card counts.
///
/// These assert the produced report, not the code that produces it: the text
/// artifact is decoded and read back.
///
/// UX-50: the totals themselves are no longer computed here — they come from
/// `GET /api/inventory/product/print-operations/summary`. What this file pins on
/// that side is the DECODE of the server's real envelope, key by key: a Dart
/// model quietly defaulting a field the server does send is exactly how three
/// customer-visible bugs shipped once before with no error anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The literal JSON of the backend's `SalesSummary` / `SalesCategoryLine`
  /// (Inventory/DTOs). Transcribed from the Java, not from the Dart model.
  Map<String, dynamic> summaryJson() => {
        'cards': 7,
        'total': 41000.0,
        'unpriced': 2,
        'notPrinted': 1,
        'byCategory': [
          {'sku': 'ASC-5000', 'category': 'Asiacell 5000', 'cards': 5, 'total': 25000.0},
          {'sku': 'ZN-10000', 'category': 'Zain 10000', 'cards': 2, 'total': 16000.0},
        ],
      };

  group('decoding the server summary', () {
    test('every figure the server sends is read, none defaulted away', () {
      final s = PosReportSummary.fromJson(summaryJson());
      expect(s.cards, 7);
      expect(s.total, 41000);
      expect(s.unpriced, 2);
      expect(s.notPrinted, 1);
      expect(s.byCategory.length, 2);
      expect(s.byCategory.first.sku, 'ASC-5000');
      expect(s.byCategory.first.category, 'Asiacell 5000');
      expect(s.byCategory.first.cards, 5);
      expect(s.byCategory.first.total, 25000);
    });

    test('the server-side order of the breakdown is preserved (busiest first)', () {
      // The backend sorts by card count and the paper report prints the rows in
      // the order it receives them; re-sorting here would make screen and paper
      // disagree for ties.
      final s = PosReportSummary.fromJson(summaryJson());
      expect(s.byCategory.map((l) => l.category).toList(),
          ['Asiacell 5000', 'Zain 10000']);
    });

    test('cards and total may legitimately disagree — unpriced sales explain it', () {
      // 7 cards but only 5 priced ones make up the money. The count is what the
      // operator reconciles the gap with, so it must survive the decode.
      final s = PosReportSummary.fromJson(summaryJson());
      final breakdownTotal =
          s.byCategory.fold<double>(0, (a, l) => a + l.total);
      expect(breakdownTotal, s.total);
      expect(s.unpriced, greaterThan(0));
    });

    test('a nameless category falls back to its SKU instead of a blank row', () {
      final s = PosReportSummary.fromJson({
        'cards': 1,
        'total': 5000.0,
        'byCategory': [
          {'sku': 'ASC-5000', 'category': null, 'cards': 1, 'total': 5000.0},
        ],
      });
      expect(s.byCategory.single.category, 'ASC-5000');
    });

    test('integral JSON numbers decode as money, not as zero', () {
      // Mongo hands back an int when a $sum lands on a whole number, and `as
      // double` on an int is a runtime failure — the totals are money, so this
      // is the path that matters most.
      final s = PosReportSummary.fromJson({'cards': 1, 'total': 5000});
      expect(s.total, 5000);
    });

    test('an empty window is a real zero, not a crash', () {
      final s = PosReportSummary.fromJson({
        'cards': 0,
        'total': 0.0,
        'unpriced': 0,
        'notPrinted': 0,
        'byCategory': <dynamic>[],
      });
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

    final oneSale = PosReportSummary.fromJson({
      'cards': 1,
      'total': 5000.0,
      'unpriced': 0,
      'notPrinted': 0,
      'byCategory': [
        {'sku': 'ASC-5000', 'category': 'Asiacell 5000', 'cards': 1, 'total': 5000.0},
      ],
    });

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
      final t = textOf(oneSale);
      expect(t, contains('محل سعد'));
      expect(t, contains('سعد عبد الله محمد'));
      expect(t, contains('وكيل الرصافة'));
      expect(t, contains('وكيل بغداد'));
    });

    test('omits an identity line it could not resolve, rather than printing it blank', () {
      // A shop may be refused the entity reads that name its agents.
      final t = textOf(oneSale, id: const PosReportIdentity(shopName: 'محل سعد'));
      expect(t, contains('محل سعد'));
      expect(t, isNot(contains('الوكيل الرئيسي')));
      expect(t, isNot(contains('صاحب النقطة')));
    });

    test('states the window and the totals it was given', () {
      final t = textOf(PosReportSummary.fromJson(summaryJson()));
      expect(t, contains('2026-07-01'));
      expect(t, contains('2026-07-30'));
      expect(t, contains('41,000'));
    });

    test('the paper never claims a partial window any more', () {
      // UX-50: the figure is a server-side aggregate over the whole window, so
      // there is no page cap left for the report to have stopped at.
      expect(textOf(PosReportSummary.fromJson(summaryJson())),
          isNot(contains('جزئي')));
    });

    test('English and Arabic differ — the report is really translated', () {
      final ar = buildSalesReportText(
        identity: identity,
        summary: oneSale,
        fromDay: '2026-07-01',
        toDay: '2026-07-30',
        printedAt: DateTime(2026, 7, 30),
        ar: true,
      );
      final en = buildSalesReportText(
        identity: identity,
        summary: oneSale,
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
      summary: PosReportSummary.fromJson({
        'cards': 1,
        'total': 5000.0,
        'byCategory': [
          {'sku': 'ASC-5000', 'category': 'اسيا سيل 5000', 'cards': 1, 'total': 5000.0},
        ],
      }),
      fromDay: '2026-07-01',
      toDay: '2026-07-30',
      printedAt: DateTime(2026, 7, 30, 14, 6),
      ar: true,
    );
    expect(job.bytes, isNotEmpty);
    expect(job.hasText, isTrue, reason: 'intent printers need the text fallback');
  });
}
