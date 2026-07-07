/// An entity's POS-user-slot quota, from `GET /api/pos-quota`. Mirrors backend
/// `Pricing/DTOs/PosSlotBalance`. `available = total − granted − used`.
class PosSlotBalance {
  final String entityId;
  final String tier;
  final int total; // slots received (root/HQ = unbounded)
  final int granted; // slots granted to children
  final int used; // POS users onboarded here
  final int available;
  final bool root;

  const PosSlotBalance({
    this.entityId = '',
    this.tier = '',
    this.total = 0,
    this.granted = 0,
    this.used = 0,
    this.available = 0,
    this.root = false,
  });

  factory PosSlotBalance.fromJson(Map<String, dynamic> j) => PosSlotBalance(
        entityId: j['entityId'] as String? ?? '',
        tier: j['tier'] as String? ?? '',
        total: (j['total'] as num?)?.toInt() ?? 0,
        granted: (j['granted'] as num?)?.toInt() ?? 0,
        used: (j['used'] as num?)?.toInt() ?? 0,
        available: (j['available'] as num?)?.toInt() ?? 0,
        root: j['root'] as bool? ?? false,
      );
}
