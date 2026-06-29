/// Result returned by `POST /api/inventory/batch/withdraw`.
/// Summarises how many AVAILABLE vouchers were reclaimed back to HQ,
/// how many were already PRINTED (sold / unreclaimable), and the full
/// batch total so the caller can surface a meaningful summary to the user.
class BatchWithdrawResult {
  final int reclaimed;
  final int used;
  final int total;
  final String batchId;

  const BatchWithdrawResult({
    required this.reclaimed,
    required this.used,
    required this.total,
    required this.batchId,
  });

  factory BatchWithdrawResult.fromJson(Map<String, dynamic> j) =>
      BatchWithdrawResult(
        reclaimed: (j['reclaimed'] as num?)?.toInt() ?? 0,
        used: (j['used'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        batchId: j['batchId'] as String? ?? '',
      );
}
