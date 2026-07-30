import 'package:inteshar/features/inventory/domain/print_operation.dart';

/// One row of the spec's per-category breakdown (سستم التقارير!A4: "تقرير
/// المبيعات يظهر … اسم الفئة وعدد الكروت").
class PosReportLine {
  final String category;
  final int cards;
  final double total;

  const PosReportLine({
    required this.category,
    required this.cards,
    required this.total,
  });
}

/// Totals for the POS التقارير window (سستم A95 + التقارير!A4).
///
/// The sales feed returns a bare list with no total, so these are derived from
/// the rows the panel actually fetched. [truncated] says so out loud when the
/// walk stopped at its page cap — a summary that silently describes only the
/// first N sales would be worse than no summary at all, because it reads as
/// authoritative.
class PosReportSummary {
  final int cards;
  final double total;
  final int notPrinted;
  final bool truncated;
  final List<PosReportLine> byCategory;

  /// Sales whose price the backend never recorded. They count as cards but
  /// contribute nothing to the money, so [cards] and [total] can legitimately
  /// disagree. Surfaced rather than hidden — an operator reconciling a till
  /// needs to know the difference is missing data, not a miscount.
  final int unpriced;

  const PosReportSummary({
    required this.cards,
    required this.total,
    required this.notPrinted,
    required this.byCategory,
    this.unpriced = 0,
    this.truncated = false,
  });

  static const empty = PosReportSummary(
    cards: 0,
    total: 0,
    notPrinted: 0,
    byCategory: [],
  );

  factory PosReportSummary.from(
    List<PrintOperation> ops, {
    bool truncated = false,
  }) {
    var total = 0.0;
    var notPrinted = 0;
    var unpriced = 0;
    final buckets = <String, ({int cards, double total})>{};

    for (final op in ops) {
      total += op.soldPrice ?? 0;
      if (op.soldPrice == null) unpriced++;
      if (!op.printed) notPrinted++;
      // productName is what the operator recognises; sku is the fallback so a
      // definition without a display name still groups instead of vanishing.
      final key = op.productName.trim().isNotEmpty ? op.productName.trim() : op.sku;
      final b = buckets[key] ?? (cards: 0, total: 0.0);
      buckets[key] = (cards: b.cards + 1, total: b.total + (op.soldPrice ?? 0));
    }

    final lines = buckets.entries
        .map((e) => PosReportLine(
              category: e.key,
              cards: e.value.cards,
              total: e.value.total,
            ))
        .toList()
      ..sort((a, b) => b.cards.compareTo(a.cards));

    return PosReportSummary(
      cards: ops.length,
      total: total,
      notPrinted: notPrinted,
      byCategory: lines,
      unpriced: unpriced,
      truncated: truncated,
    );
  }
}

/// The identity block the spec puts on EVERY report (سستم التقارير!A1: "أي تقرير
/// يجب ان يحتوي على الاسم التجاري لنقطة البيع مع الاسم الثلاثي واسم الوكيل
/// الرئيسي والفرعي").
///
/// Every field is optional because the POS can only resolve what it is allowed
/// to read: the shop is always known, the owner comes from an optional profile,
/// and the agent chain needs entity reads that a shop may be refused. A missing
/// line is omitted rather than printed blank.
class PosReportIdentity {
  final String shopName;
  final String ownerName;
  final String subAgentName;
  final String mainAgentName;

  const PosReportIdentity({
    this.shopName = '',
    this.ownerName = '',
    this.subAgentName = '',
    this.mainAgentName = '',
  });

  bool get isEmpty =>
      shopName.trim().isEmpty &&
      ownerName.trim().isEmpty &&
      subAgentName.trim().isEmpty &&
      mainAgentName.trim().isEmpty;
}
