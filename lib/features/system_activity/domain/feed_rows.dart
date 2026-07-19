import 'package:inteshar/features/entities/domain/entity_type.dart';

// EntitySummaryRow moved to the entities domain (B-023: it now also backs the
// picker search + lazy tree); re-exported here so existing imports keep working.
export 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';

/// Projected transaction row from `GET /api/transactions/feed`. The server drops
/// the `lines[]` array, pre-computes the totals, and denormalises the
/// source/destination names — so the list needs neither the line items nor the
/// entity list. The detail sheet fetches the full document on tap.
class TransactionFeedRow {
  final String id;
  final String date;
  final String time;
  final String sourceId;
  final String sourceName;
  final String destinationId;
  final String destinationName;
  final String status;
  final int lineCount;
  final int totalUnits;
  final int totalAmount;

  const TransactionFeedRow({
    this.id = '',
    this.date = '',
    this.time = '',
    this.sourceId = '',
    this.sourceName = '',
    this.destinationId = '',
    this.destinationName = '',
    this.status = 'PENDING',
    this.lineCount = 0,
    this.totalUnits = 0,
    this.totalAmount = 0,
  });

  TransactionStatus get statusEnum => TransactionStatus.values.firstWhere(
        (e) => e.name == status,
        orElse: () => TransactionStatus.PENDING,
      );

  String get sourceLabel => sourceName.isNotEmpty ? sourceName : sourceId;
  String get destinationLabel =>
      destinationName.isNotEmpty ? destinationName : destinationId;

  factory TransactionFeedRow.fromJson(Map<String, dynamic> j) => TransactionFeedRow(
        id: j['id'] as String? ?? '',
        date: j['date'] as String? ?? '',
        time: j['time'] as String? ?? '',
        sourceId: j['sourceId'] as String? ?? '',
        sourceName: j['sourceName'] as String? ?? '',
        destinationId: j['destinationId'] as String? ?? '',
        destinationName: j['destinationName'] as String? ?? '',
        status: j['status'] as String? ?? 'PENDING',
        lineCount: (j['lineCount'] as num?)?.toInt() ?? 0,
        totalUnits: (j['totalUnits'] as num?)?.toInt() ?? 0,
        totalAmount: (j['totalAmount'] as num?)?.toInt() ?? 0,
      );
}


/// A user flattened out of its owning entity by `GET /api/admin/users`
/// (password-free by construction on the server).
class AdminUserRow {
  final String id;
  final String phone;
  final String role; // ADMIN | USER
  final String entityId;
  final String entityName;
  final String entityType;

  const AdminUserRow({
    this.id = '',
    this.phone = '',
    this.role = 'USER',
    this.entityId = '',
    this.entityName = '',
    this.entityType = '',
  });

  UserRole get roleEnum =>
      role == 'ADMIN' ? UserRole.ADMIN : UserRole.USER;

  EntityType? get entityTypeEnum {
    for (final t in EntityType.values) {
      if (t.name == entityType) return t;
    }
    return null;
  }

  String get entityLabel => entityName.isNotEmpty ? entityName : entityId;

  factory AdminUserRow.fromJson(Map<String, dynamic> j) => AdminUserRow(
        id: j['id'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        role: j['role'] as String? ?? 'USER',
        entityId: j['entityId'] as String? ?? '',
        entityName: j['entityName'] as String? ?? '',
        entityType: j['entityType'] as String? ?? '',
      );
}
