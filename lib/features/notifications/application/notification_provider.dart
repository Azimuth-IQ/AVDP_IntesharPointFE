import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';

/// Unread notification count for the signed-in entity.
///
/// Fetches the first page of the inbox (up to 50 items) and counts how many
/// are unread. Returns 0 silently on any network or auth error so badge
/// failures remain invisible to the user.
///
/// After a successful [NotificationRepository.markRead] call, invalidate this
/// provider to refresh the nav-item badge:
/// ```dart
/// ref.invalidate(notificationsUnreadCountProvider);
/// ```
///
/// [app_scaffold.dart] can watch this provider to show a badge count on the
/// Notifications nav item:
/// ```dart
/// final countAsync = ref.watch(notificationsUnreadCountProvider);
/// final count = countAsync.valueOrNull ?? 0;
/// ```
final notificationsUnreadCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final paged =
        await NotificationRepository(api).inbox(page: 0, size: 50);
    return paged.items.where((n) => !n.isRead).length;
  } catch (_) {
    return 0;
  }
});

/// B-060: the unread ALERT notifications for the signed-in entity, newest first.
/// Alerts render as a prominent banner (see AlertBanner); dismissing one marks it
/// read, which — after invalidating this provider — removes it from the banner.
final unreadAlertsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final paged = await NotificationRepository(api).inbox(page: 0, size: 50);
    return paged.items
        .where((n) => n.type == 'ALERT' && !n.isRead)
        .toList();
  } catch (_) {
    return const [];
  }
});
