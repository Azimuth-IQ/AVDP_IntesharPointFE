import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/features/system_activity/domain/operation_log.dart';
import 'package:inteshar/features/system_activity/domain/system_overview.dart';

/// BFF client for the HQ "System Activity" screen. Every call is admin-only and
/// returns a projected / paged payload, so the screen never downloads the heavy
/// `readall` collections. See `Docs/system-activity-backend-endpoints.txt`.
class SystemActivityRepository {
  final ApiClient _api;
  SystemActivityRepository(this._api);

  /// Default page size; the backend caps it at 200.
  static const int pageSize = 50;

  // ── KPIs ───────────────────────────────────────────────────────────────────

  Future<SystemOverview> overview() async {
    final r = await _api.get(Endpoints.adminOverview);
    return _api.unwrap(r, (d) => SystemOverview.fromJson(d as Map<String, dynamic>));
  }

  // ── Activity log ─────────────────────────────────────────────────────────────

  /// Projected, paged log rows. Filters are applied server-side.
  Future<Paged<OperationLog>> logs({
    String? level,
    bool? success,
    String? path,
    String? platform,
    String? entityId,
    int page = 0,
    int size = pageSize,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (level != null && level.isNotEmpty) params['level'] = level;
    if (success != null) params['success'] = success;
    if (path != null && path.isNotEmpty) params['path'] = path;
    if (platform != null && platform.isNotEmpty) params['platform'] = platform;
    if (entityId != null && entityId.isNotEmpty) params['entityId'] = entityId;
    final r = await _api.get(Endpoints.logQuery, params: params);
    return _api.unwrap(r, (d) => Paged.from(d, OperationLog.fromJson, size: size));
  }

  /// The full log document (heavy fields included) for the detail sheet.
  Future<OperationLog> logDetail(String id) async {
    final r = await _api.get(Endpoints.logRead, params: {'id': id});
    return _api.unwrap(r, (d) => OperationLog.fromJson(d as Map<String, dynamic>));
  }

  // ── Transactions feed ─────────────────────────────────────────────────────────

  Future<Paged<TransactionFeedRow>> transactions({
    String? status,
    String? entityId,
    int page = 0,
    int size = pageSize,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (entityId != null && entityId.isNotEmpty) params['entityId'] = entityId;
    final r = await _api.get(Endpoints.transactionFeed, params: params);
    return _api.unwrap(r, (d) => Paged.from(d, TransactionFeedRow.fromJson, size: size));
  }

  // ── Entities feed ──────────────────────────────────────────────────────────────

  Future<Paged<EntitySummaryRow>> entities({
    String? type,
    String? search,
    int page = 0,
    int size = pageSize,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final r = await _api.get(Endpoints.entitySummary, params: params);
    return _api.unwrap(r, (d) => Paged.from(d, EntitySummaryRow.fromJson, size: size));
  }

  // ── Users feed ────────────────────────────────────────────────────────────────

  Future<Paged<AdminUserRow>> users({
    String? phone,
    String? role,
    String? entityId,
    int page = 0,
    int size = pageSize,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (phone != null && phone.isNotEmpty) params['phone'] = phone;
    if (role != null && role.isNotEmpty) params['role'] = role;
    if (entityId != null && entityId.isNotEmpty) params['entityId'] = entityId;
    final r = await _api.get(Endpoints.adminUsers, params: params);
    return _api.unwrap(r, (d) => Paged.from(d, AdminUserRow.fromJson, size: size));
  }
}
