/// One catalog row: a category, its company, official + own price, and the entity's
/// available stock / line value. Mirrors backend `Pricing/DTOs/CategoryPriceRow`.
class CategoryPriceRow {
  final String sku;
  final String name;
  final String companyId;
  final String companyName;
  final num officialPrice;
  final num? agentPrice; // null = the entity hasn't set its own price
  final num effectivePrice;
  final int available;
  final num lineValue;
  final bool priced;

  const CategoryPriceRow({
    this.sku = '',
    this.name = '',
    this.companyId = '',
    this.companyName = '',
    this.officialPrice = 0,
    this.agentPrice,
    this.effectivePrice = 0,
    this.available = 0,
    this.lineValue = 0,
    this.priced = false,
  });

  factory CategoryPriceRow.fromJson(Map<String, dynamic> j) => CategoryPriceRow(
        sku: j['sku'] as String? ?? '',
        name: j['name'] as String? ?? '',
        companyId: j['companyId'] as String? ?? '',
        companyName: j['companyName'] as String? ?? '',
        officialPrice: (j['officialPrice'] as num?) ?? 0,
        agentPrice: j['agentPrice'] as num?,
        effectivePrice: (j['effectivePrice'] as num?) ?? 0,
        available: (j['available'] as num?)?.toInt() ?? 0,
        lineValue: (j['lineValue'] as num?) ?? 0,
        priced: j['priced'] as bool? ?? false,
      );
}

class PricingCatalog {
  final List<CategoryPriceRow> rows;
  final num inventoryWorth;
  final int unpricedCount;

  const PricingCatalog({this.rows = const [], this.inventoryWorth = 0, this.unpricedCount = 0});

  factory PricingCatalog.fromJson(Map<String, dynamic> j) => PricingCatalog(
        rows: ((j['rows'] as List<dynamic>?) ?? const [])
            .map((e) => CategoryPriceRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        inventoryWorth: (j['inventoryWorth'] as num?) ?? 0,
        unpricedCount: (j['unpricedCount'] as num?)?.toInt() ?? 0,
      );
}

/// An entity's balance snapshot. `inventoryBacked` true for HQ/Main Agent (worth);
/// false for Sub/Store (funded wallet).
class AgentBalance {
  final String entityId;
  final String tier;
  final num base;
  final num grantsOut;
  final num available;
  final bool inventoryBacked;

  const AgentBalance({
    this.entityId = '',
    this.tier = '',
    this.base = 0,
    this.grantsOut = 0,
    this.available = 0,
    this.inventoryBacked = false,
  });

  factory AgentBalance.fromJson(Map<String, dynamic> j) => AgentBalance(
        entityId: j['entityId'] as String? ?? '',
        tier: j['tier'] as String? ?? '',
        base: (j['base'] as num?) ?? 0,
        grantsOut: (j['grantsOut'] as num?) ?? 0,
        available: (j['available'] as num?) ?? 0,
        inventoryBacked: j['inventoryBacked'] as bool? ?? false,
      );
}

/// A balance-grant ledger row (with resolved names) from `GET /api/balance/grants`.
class GrantRow {
  final String id;
  final String date;
  final String time;
  final String sourceId;
  final String sourceName;
  final String destId;
  final String destName;
  final num amount;
  final String direction; // OUT | IN relative to the viewer

  const GrantRow({
    this.id = '',
    this.date = '',
    this.time = '',
    this.sourceId = '',
    this.sourceName = '',
    this.destId = '',
    this.destName = '',
    this.amount = 0,
    this.direction = 'OUT',
  });

  factory GrantRow.fromJson(Map<String, dynamic> j) => GrantRow(
        id: j['id'] as String? ?? '',
        date: j['date'] as String? ?? '',
        time: j['time'] as String? ?? '',
        sourceId: j['sourceId'] as String? ?? '',
        sourceName: j['sourceName'] as String? ?? '',
        destId: j['destId'] as String? ?? '',
        destName: j['destName'] as String? ?? '',
        amount: (j['amount'] as num?) ?? 0,
        direction: j['direction'] as String? ?? 'OUT',
      );
}
