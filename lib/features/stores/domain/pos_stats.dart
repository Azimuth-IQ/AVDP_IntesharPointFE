/// Operational snapshot for a single POS point (STORE), from `GET /api/entity/posStats`.
/// Read-only aggregation of last-activity/device context (operation_logs), voucher
/// counts (products) and the virtual balance.
class PosStats {
  final bool active;
  final String? lastSeenAt;       // ISO timestamp of the point's most recent request
  final String? lastDeviceModel;
  final String? lastAppVersion;
  final String? lastPlatform;
  final int printedCount;          // vouchers sold (PRINTED)
  final int availableCount;        // sellable stock (AVAILABLE)
  final double balanceAvailable;

  const PosStats({
    this.active = true,
    this.lastSeenAt,
    this.lastDeviceModel,
    this.lastAppVersion,
    this.lastPlatform,
    this.printedCount = 0,
    this.availableCount = 0,
    this.balanceAvailable = 0,
  });

  factory PosStats.fromJson(Map<String, dynamic> j) => PosStats(
        active: j['active'] as bool? ?? true,
        lastSeenAt: j['lastSeenAt'] as String?,
        lastDeviceModel: j['lastDeviceModel'] as String?,
        lastAppVersion: j['lastAppVersion'] as String?,
        lastPlatform: j['lastPlatform'] as String?,
        printedCount: (j['printedCount'] as num?)?.toInt() ?? 0,
        availableCount: (j['availableCount'] as num?)?.toInt() ?? 0,
        balanceAvailable: (j['balanceAvailable'] as num?)?.toDouble() ?? 0,
      );
}
