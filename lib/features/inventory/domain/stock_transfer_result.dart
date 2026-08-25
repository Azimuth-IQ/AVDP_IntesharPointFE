/// What came of moving stock straight from one agent to another (C-19).
///
/// Shaped like `StockWithdrawResult`, with one field the others do not need.
/// A transfer is a DELIVERY, so the server only sends cards the destination could
/// actually sell — region-locked stock outside their governorates, expired cards
/// and supplier-recalled batches stay put. That means [moved] can be 0 while the
/// agent is nowhere near out of stock.
///
/// [deliverable] is what separates those two cases. Without it the UI can only say
/// "Transferred 0 of 50", which reads as a broken button rather than a geo-lock
/// doing its job.
class StockTransferResult {
  final String fromEntityId;
  final String toEntityId;
  final String sku;
  final String? governorate;
  final int requested;
  final int moved;

  /// Still with the source and sellable after this — to any destination.
  final int remaining;

  /// Of [remaining], how many could still go to THIS destination.
  final int deliverable;

  const StockTransferResult({
    this.fromEntityId = '',
    this.toEntityId = '',
    this.sku = '',
    this.governorate,
    this.requested = 0,
    this.moved = 0,
    this.remaining = 0,
    this.deliverable = 0,
  });

  /// Fewer moved than were asked for — worth saying out loud.
  bool get isShort => moved < requested;

  /// Nothing moved, but not because the shelf is empty: the destination cannot
  /// sell what this agent is holding.
  bool get blockedByRegion => moved == 0 && remaining > 0 && deliverable == 0;

  factory StockTransferResult.fromJson(Map<String, dynamic> j) =>
      StockTransferResult(
        fromEntityId: j['fromEntityId'] as String? ?? '',
        toEntityId: j['toEntityId'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        governorate: j['governorate'] as String?,
        requested: (j['requested'] as num?)?.toInt() ?? 0,
        moved: (j['moved'] as num?)?.toInt() ?? 0,
        remaining: (j['remaining'] as num?)?.toInt() ?? 0,
        deliverable: (j['deliverable'] as num?)?.toInt() ?? 0,
      );
}
