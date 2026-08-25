/// A governorate sub-bucket within a [SkuSummary] — the voucher's governorate is the
/// subcategory of its category (SKU). `governorate` '' = untagged / region-free.
class GovBucket {
  final String governorate;
  final int total;
  final int available;
  final int printed;
  final int damaged;
  final int sentForPrinting;
  final int failedPrinting;

  /// C-19: pulled out of circulation by HQ. Never sellable, still part of [total]
  /// — without its own field the card's total stops equalling its pills.
  final int retired;
  final num availableValue; // available * EFFECTIVE price (per-gov override ?? SKU-wide base ?? default), set by the backend

  const GovBucket({
    this.governorate = '',
    this.total = 0,
    this.available = 0,
    this.printed = 0,
    this.damaged = 0,
    this.sentForPrinting = 0,
    this.failedPrinting = 0,
    this.retired = 0,
    this.availableValue = 0,
  });

  bool get isUntagged => governorate.isEmpty;

  factory GovBucket.fromJson(Map<String, dynamic> j) => GovBucket(
        governorate: j['governorate'] as String? ?? '',
        total: (j['total'] as num?)?.toInt() ?? 0,
        available: (j['available'] as num?)?.toInt() ?? 0,
        printed: (j['printed'] as num?)?.toInt() ?? 0,
        damaged: (j['damaged'] as num?)?.toInt() ?? 0,
        sentForPrinting: (j['sentForPrinting'] as num?)?.toInt() ?? 0,
        failedPrinting: (j['failedPrinting'] as num?)?.toInt() ?? 0,
        retired: (j['retired'] as num?)?.toInt() ?? 0,
        availableValue: (j['availableValue'] as num?) ?? 0,
      );
}

/// Per-SKU rollup for an entity's inventory, returned by the backend
/// `product/summaryByEntity` aggregation. The SKU-level counts are the sum of the
/// per-governorate [governorates] buckets (governorate = the voucher subcategory).
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

  /// C-19: pulled out of circulation by HQ — counted in [total], never sellable.
  final int retired;
  final List<GovBucket> governorates;

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
    this.retired = 0,
    this.governorates = const [],
  });

  /// Value of sellable (AVAILABLE) stock for this SKU, at the entity's EFFECTIVE price.
  /// Sums the per-governorate buckets — the backend prices each bucket at the effective
  /// per-agent price (override ?? SKU-wide base ?? defaultPrice), so this agrees with the
  /// pricing screen + balance. Falls back to `available * defaultPrice` when there are no
  /// buckets (older backend / empty response) so the value card never drops to 0 mid-rollout.
  num get availableValue => governorates.isEmpty
      ? available * defaultPrice
      : governorates.fold<num>(0, (s, b) => s + b.availableValue);

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
        retired: (j['retired'] as num?)?.toInt() ?? 0,
        governorates: ((j['governorates'] as List<dynamic>?) ?? const [])
            .map((e) => GovBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
