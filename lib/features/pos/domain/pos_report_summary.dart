/// One row of the spec's per-category breakdown (سستم التقارير!A4: "تقرير
/// المبيعات يظهر … اسم الفئة وعدد الكروت").
///
/// [sku] is the stable key the server groups on; [category] is the operator-facing
/// product name, which falls back to the SKU so a definition with no display name
/// still gets a row instead of vanishing into a blank bucket.
class PosReportLine {
  final String sku;
  final String category;
  final int cards;
  final double total;

  const PosReportLine({
    this.sku = '',
    required this.category,
    required this.cards,
    required this.total,
  });

  factory PosReportLine.fromJson(Map<String, dynamic> j) {
    final sku = j['sku'] as String? ?? '';
    final name = (j['category'] as String? ?? '').trim();
    return PosReportLine(
      sku: sku,
      category: name.isNotEmpty ? name : sku,
      cards: (j['cards'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Totals for the POS التقارير window (سستم A95 + التقارير!A4) — the server's
/// `SalesSummary` for exactly the window the list under it is showing.
///
/// UX-50: these used to be added up on the handheld by fetching up to 40 pages of
/// the feed, and were labelled "partial" when the walk ran out of pages. The
/// figures now come from one `$group` over the same criteria as the feed, so the
/// total cannot describe a different set of sales than the rows listed under it.
class PosReportSummary {
  final int cards;
  final double total;
  final int notPrinted;
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
  });

  static const empty = PosReportSummary(
    cards: 0,
    total: 0,
    notPrinted: 0,
    byCategory: [],
  );

  /// The server's `SalesSummary` envelope:
  /// `{cards, total, unpriced, notPrinted, byCategory:[{sku, category, cards, total}]}`.
  /// The category rows arrive busiest-first and that order is kept — it is the
  /// order the paper report prints them in.
  factory PosReportSummary.fromJson(Map<String, dynamic> j) => PosReportSummary(
        cards: (j['cards'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        notPrinted: (j['notPrinted'] as num?)?.toInt() ?? 0,
        unpriced: (j['unpriced'] as num?)?.toInt() ?? 0,
        byCategory: ((j['byCategory'] as List<dynamic>?) ?? const [])
            .map((e) => PosReportLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
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
