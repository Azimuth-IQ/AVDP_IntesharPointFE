/// Read-only operational snapshot for ONE shop, from `GET /api/entity/posStats`.
/// Mirrors backend `Entity/DTOs/PosStats`.
///
/// UX-07: this endpoint has existed on the server (and as an `Endpoints`
/// constant) the whole time and nothing in the app ever called it — which is why
/// "why can't this shop sell?" was a six-screen scavenger hunt. It is gated
/// HQ-or-self-or-descendant, NOT `VIEW_REPORTS`, so any manager who can see the
/// shop in their list can also see its diagnostics.
class PosStats {
  final bool active;

  /// Most recent authenticated request by any of this shop's users — the only
  /// "is anybody actually using this point" signal the platform holds.
  final String lastSeenAt;
  final String lastDeviceModel;
  final String lastAppVersion;
  final String lastPlatform;

  /// Vouchers sold (status PRINTED) that this shop owns — its lifetime sales.
  final int printedCount;

  /// Cards the shop holds itself. Draw-on-print shops sell from their parent's
  /// pool, so this is legitimately 0 for most points and must NOT be presented
  /// as "out of stock" on its own.
  final int availableCount;

  final num balanceAvailable;

  const PosStats({
    this.active = true,
    this.lastSeenAt = '',
    this.lastDeviceModel = '',
    this.lastAppVersion = '',
    this.lastPlatform = '',
    this.printedCount = 0,
    this.availableCount = 0,
    this.balanceAvailable = 0,
  });

  factory PosStats.fromJson(Map<String, dynamic> j) => PosStats(
        active: j['active'] as bool? ?? true,
        lastSeenAt: j['lastSeenAt']?.toString() ?? '',
        lastDeviceModel: j['lastDeviceModel'] as String? ?? '',
        lastAppVersion: j['lastAppVersion'] as String? ?? '',
        lastPlatform: j['lastPlatform'] as String? ?? '',
        printedCount: (j['printedCount'] as num?)?.toInt() ?? 0,
        availableCount: (j['availableCount'] as num?)?.toInt() ?? 0,
        balanceAvailable: (j['balanceAvailable'] as num?) ?? 0,
      );
}
