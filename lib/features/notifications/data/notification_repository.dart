import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';

/// Client for the `/api/notifications` backend slice.
///
/// The backend enforces auth: only an HQ ADMIN may call [send]; [inbox] and
/// [markRead] are available to any authenticated entity (scoped server-side by
/// the JWT to notifications whose audience includes the caller's type/id).
///
/// All responses use the standard `{status, message, data}` envelope unwrapped
/// via [ApiClient.unwrap].
class NotificationRepository {
  final ApiClient _api;
  NotificationRepository(this._api);

  static const int defaultPageSize = 30;

  /// Returns the paged notification inbox for the current entity.
  /// Each item's [AppNotification.isRead] reflects whether the current caller
  /// has read it.
  Future<Paged<AppNotification>> inbox({
    int page = 0,
    int size = defaultPageSize,
  }) async {
    final r = await _api.get(
      Endpoints.notifications,
      params: {'page': page, 'size': size},
    );
    return _api.unwrap(
      r,
      (d) => Paged.from(d, AppNotification.fromJson, size: size),
    );
  }

  /// Sends a broadcast notification (HQ-admin only; backend enforces).
  ///
  /// [audienceType] must be `ALL`, `TIER`, or `ENTITY`.
  /// [tierTypes] carries one or more EntityType names when [audienceType] == `TIER`.
  /// [entityIds] carries one or more target ids when [audienceType] == `ENTITY`.
  /// [posOnly] narrows any audience to POS operators (User.isPos) within the scope.
  ///
  /// UX-88: returns the server's delivery tally so the confirmation can name the
  /// audience size. The body used to be discarded; a backend that has not been
  /// redeployed yet still answers with the bare notification, which parses to a
  /// [NotificationReach] with `hasTally == false` rather than to zeros.
  Future<NotificationReach> send({
    required String title,
    required String body,
    required String audienceType,
    List<String> tierTypes = const [],
    List<String> entityIds = const [],
    bool posOnly = false,
    String type = 'NOTIFICATION',
  }) async {
    final r = await _api.post(Endpoints.notificationsSend, data: {
      'title': title,
      'body': body,
      'audience': audienceType,
      'type': type,
      if (tierTypes.isNotEmpty) 'tierTypes': tierTypes,
      if (entityIds.isNotEmpty) 'entityIds': entityIds,
      if (posOnly) 'posOnly': true,
    });
    return _api.unwrap(
      r,
      (d) => d is Map
          ? NotificationReach.fromJson(d.cast<String, dynamic>())
          : const NotificationReach(),
    );
  }

  /// Marks [id] as read for the current caller.
  /// POST /api/notifications/{id}/read (idempotent, no body).
  Future<void> markRead(String id) async {
    await _api.post('${Endpoints.notifications}/$id/read');
  }
}
