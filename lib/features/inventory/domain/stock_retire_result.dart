/// What came of taking stock out of circulation for good (C-19).
///
/// Shaped like `StockWithdrawResult` and reported the same way: [retired] can be
/// fewer than [requested] because the agent may hold fewer, or some may have sold
/// between looking and pressing.
class StockRetireResult {
  final String fromEntityId;
  final String sku;
  final String? governorate;
  final int requested;
  final int retired;

  /// Still with the agent and sellable after this.
  final int remaining;

  /// Handle for the undo. Null when nothing moved, so the UI never offers to
  /// restore a lot that does not exist.
  final String? retireRef;

  const StockRetireResult({
    this.fromEntityId = '',
    this.sku = '',
    this.governorate,
    this.requested = 0,
    this.retired = 0,
    this.remaining = 0,
    this.retireRef,
  });

  /// Fewer moved than were asked for — worth saying out loud.
  bool get isShort => retired < requested;

  factory StockRetireResult.fromJson(Map<String, dynamic> j) => StockRetireResult(
        fromEntityId: j['fromEntityId'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        governorate: j['governorate'] as String?,
        requested: (j['requested'] as num?)?.toInt() ?? 0,
        retired: (j['retired'] as num?)?.toInt() ?? 0,
        remaining: (j['remaining'] as num?)?.toInt() ?? 0,
        retireRef: j['retireRef'] as String?,
      );
}

/// One retire action still standing — the unit HQ restores.
///
/// Grouped by `retireRef` rather than card by card: an operator who pulled 500
/// cards by mistake wants to put back that action, not tick 500 serials.
class RetiredLot {
  final String retireRef;
  final String sku;
  final String productName;
  final String? governorate;

  /// The account the cards came from — where a restore puts them back.
  final String retiredFrom;
  final String retiredFromName;
  final String retiredBy;
  final int count;
  final DateTime? retiredAt;

  const RetiredLot({
    this.retireRef = '',
    this.sku = '',
    this.productName = '',
    this.governorate,
    this.retiredFrom = '',
    this.retiredFromName = '',
    this.retiredBy = '',
    this.count = 0,
    this.retiredAt,
  });

  /// Falls back to the id when the account has no name, so a row is never blank.
  String get displayFrom =>
      retiredFromName.isNotEmpty ? retiredFromName : retiredFrom;

  factory RetiredLot.fromJson(Map<String, dynamic> j) => RetiredLot(
        retireRef: j['retireRef'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        productName: j['productName'] as String? ?? '',
        governorate: j['governorate'] as String?,
        retiredFrom: j['retiredFrom'] as String? ?? '',
        retiredFromName: j['retiredFromName'] as String? ?? '',
        retiredBy: j['retiredBy'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        retiredAt: j['retiredAt'] == null
            ? null
            : DateTime.tryParse(j['retiredAt'].toString()),
      );
}
