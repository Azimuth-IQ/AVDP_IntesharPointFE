import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';

/// The notifications repository, injectable so the banner can be tested without a
/// network.
final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(apiClientProvider)),
);

/// The first page of the signed-in entity's inbox (up to 50 items) — fetched ONCE
/// and shared by the nav badge and the alert banner.
///
/// Those two used to fetch the identical page side by side, so every shell load,
/// every banner dismissal and every push ping cost two GETs instead of one. On a
/// POS handheld over a mobile link that is the difference that shows. To refresh
/// either, invalidate THIS provider; the derived ones below follow.
///
/// Any network or auth error yields an empty page, so a failed fetch can never
/// break the navigation or the screen the banner sits on.
final inboxHeadProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  try {
    final paged = await ref.watch(notificationRepositoryProvider).inbox(page: 0, size: 50);
    return paged.items;
  } catch (_) {
    return const [];
  }
});

/// Unread notification count for the signed-in entity (the nav-item badge).
///
/// Derived from [inboxHeadProvider]; returns 0 silently on any failure so badge
/// failures remain invisible to the user.
final notificationsUnreadCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final items = await ref.watch(inboxHeadProvider.future);
  return items.where((n) => !n.isRead).length;
});

/// B-060: the unread ALERT notifications for the signed-in entity, newest first.
/// Alerts render as a prominent banner (see AlertBanner); dismissing one marks it
/// read, which — after invalidating [inboxHeadProvider] — removes it from the banner.
final unreadAlertsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final items = await ref.watch(inboxHeadProvider.future);
  return items.where((n) => n.type == 'ALERT' && !n.isRead).toList();
});
