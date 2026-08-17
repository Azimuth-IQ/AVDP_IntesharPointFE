/// A point of sale that has been retired and is waiting out its retention
/// window before permanent deletion.
///
/// [daysRemaining] and [purgeable] are computed by the server against the same
/// clock and retention setting the purge endpoint enforces. The client must not
/// recompute them: a locally-derived countdown eventually offers a delete button
/// the server refuses.
class ArchivedPos {
  final String id;
  final String name;
  final String? governorate;
  final String? hostId;
  final String? hostName;
  final String? operatorPhone;
  final String? ownerName;
  final DateTime? archivedAt;
  final String? archivedBy;
  final int daysRemaining;
  final bool purgeable;

  const ArchivedPos({
    required this.id,
    required this.name,
    this.governorate,
    this.hostId,
    this.hostName,
    this.operatorPhone,
    this.ownerName,
    this.archivedAt,
    this.archivedBy,
    this.daysRemaining = 0,
    this.purgeable = false,
  });

  factory ArchivedPos.fromJson(Map<String, dynamic> j) => ArchivedPos(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        governorate: j['governorate'] as String?,
        hostId: j['hostId'] as String?,
        hostName: j['hostName'] as String?,
        operatorPhone: j['operatorPhone'] as String?,
        ownerName: j['ownerName'] as String?,
        archivedAt: j['archivedAt'] == null
            ? null
            : DateTime.tryParse(j['archivedAt'].toString()),
        archivedBy: j['archivedBy'] as String?,
        daysRemaining: (j['daysRemaining'] as num?)?.toInt() ?? 0,
        purgeable: j['purgeable'] as bool? ?? false,
      );
}

/// Everything the platform holds about one shop, fetched so it can be saved
/// before archiving starts the countdown to deletion.
class PosDataExport {
  final Map<String, dynamic> raw;
  const PosDataExport(this.raw);

  String get name => raw['name'] as String? ?? '';
  String? get ownerName => raw['ownerName'] as String?;
  String? get hostName => raw['hostName'] as String?;
  String? get operatorPhone => raw['operatorPhone'] as String?;
  String? get address => raw['address'] as String?;
  String? get governorate => raw['governorate'] as String?;
  double get balanceAvailable => (raw['balanceAvailable'] as num?)?.toDouble() ?? 0;
  double get balanceReceived => (raw['balanceReceived'] as num?)?.toDouble() ?? 0;
  double get balanceSpent => (raw['balanceSpent'] as num?)?.toDouble() ?? 0;

  List<Map<String, dynamic>> get sales =>
      ((raw['sales'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get grants =>
      ((raw['grants'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>();

  factory PosDataExport.fromJson(Map<String, dynamic> j) => PosDataExport(j);
}
