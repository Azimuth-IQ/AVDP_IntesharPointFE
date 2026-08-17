/// What actually came back when stock was pulled from an agent's warehouse.
///
/// [reclaimed] can be fewer than [requested] — the agent may hold fewer than the
/// screen showed, or some may have sold in between. Both numbers are reported so
/// a short result can be explained rather than passed off as success.
class StockWithdrawResult {
  final String sku;
  final String? governorate;
  final int requested;
  final int reclaimed;
  final int remaining;

  const StockWithdrawResult({
    required this.sku,
    this.governorate,
    required this.requested,
    required this.reclaimed,
    required this.remaining,
  });

  bool get isShort => reclaimed < requested;

  factory StockWithdrawResult.fromJson(Map<String, dynamic> j) => StockWithdrawResult(
        sku: j['sku'] as String? ?? '',
        governorate: j['governorate'] as String?,
        requested: (j['requested'] as num?)?.toInt() ?? 0,
        reclaimed: (j['reclaimed'] as num?)?.toInt() ?? 0,
        remaining: (j['remaining'] as num?)?.toInt() ?? 0,
      );
}
