/// Per-SKU rollup for an entity's inventory, returned by the backend
/// `product/summaryByEntity` aggregation. Lets the inventory page render grouped
/// cards, tallies and total value without downloading every voucher document.
class SkuSummary {
  final String sku;
  final String name;
  final num defaultPrice;
  final int total;
  final int available;
  final int printed;
  final int damaged;
  final int sentForPrinting;
  final int failedPrinting;

  const SkuSummary({
    required this.sku,
    this.name = '',
    this.defaultPrice = 0,
    this.total = 0,
    this.available = 0,
    this.printed = 0,
    this.damaged = 0,
    this.sentForPrinting = 0,
    this.failedPrinting = 0,
  });

  /// Value of sellable (AVAILABLE) stock for this SKU.
  num get availableValue => available * defaultPrice;

  factory SkuSummary.fromJson(Map<String, dynamic> j) => SkuSummary(
        sku: j['sku'] as String? ?? '',
        name: j['name'] as String? ?? '',
        defaultPrice: (j['defaultPrice'] as num?) ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        available: (j['available'] as num?)?.toInt() ?? 0,
        printed: (j['printed'] as num?)?.toInt() ?? 0,
        damaged: (j['damaged'] as num?)?.toInt() ?? 0,
        sentForPrinting: (j['sentForPrinting'] as num?)?.toInt() ?? 0,
        failedPrinting: (j['failedPrinting'] as num?)?.toInt() ?? 0,
      );
}
