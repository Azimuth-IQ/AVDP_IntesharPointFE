/// Mirror of the backend `OverviewResponse` (`GET /api/admin/overview`) — the
/// one small payload powering the stat strip and tab-count badges, so the screen
/// never downloads every entity / transaction just to render numbers.
///
/// The `activity*` fields are nullable: the backend may omit the windowed log
/// facets, in which case the Errors-window tile is hidden.
class SystemOverview {
  final int entityTotal;
  final Map<String, int> entityByType; // INTESHAR | AGENT1 | AGENT2 | STORE
  final int userTotal;
  final int userAdmins;
  final int txnTotal;
  final Map<String, int> txnByStatus; // PENDING | PROCESSING | COMPLETED | FAILED
  final int? activityWindowHours;
  final int? activityEvents;
  final int? activityErrors;
  final int? activityWarnings;

  const SystemOverview({
    this.entityTotal = 0,
    this.entityByType = const {},
    this.userTotal = 0,
    this.userAdmins = 0,
    this.txnTotal = 0,
    this.txnByStatus = const {},
    this.activityWindowHours,
    this.activityEvents,
    this.activityErrors,
    this.activityWarnings,
  });

  int get storeCount => entityByType['STORE'] ?? 0;
  int get failedTxnCount => txnByStatus['FAILED'] ?? 0;
  bool get hasActivity => activityEvents != null || activityErrors != null;

  factory SystemOverview.fromJson(Map<String, dynamic> j) {
    Map<String, int> intMap(dynamic m) =>
        (m as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)) ??
        const {};
    int? asInt(dynamic v) => (v as num?)?.toInt();

    final e = j['entities'] as Map<String, dynamic>? ?? const {};
    final u = j['users'] as Map<String, dynamic>? ?? const {};
    final t = j['transactions'] as Map<String, dynamic>? ?? const {};
    final a = j['activity'] as Map<String, dynamic>?;

    return SystemOverview(
      entityTotal: asInt(e['total']) ?? 0,
      entityByType: intMap(e['byType']),
      userTotal: asInt(u['total']) ?? 0,
      userAdmins: asInt(u['admins']) ?? 0,
      txnTotal: asInt(t['total']) ?? 0,
      txnByStatus: intMap(t['byStatus']),
      activityWindowHours: a == null ? null : asInt(a['windowHours']),
      activityEvents: a == null ? null : asInt(a['events']),
      activityErrors: a == null ? null : asInt(a['errors']),
      activityWarnings: a == null ? null : asInt(a['warnings']),
    );
  }
}
