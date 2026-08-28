import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/notifications/application/notification_provider.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';

/// Alerts dismissed this session — so a dismiss sticks even when the markRead call
/// fails offline (otherwise the refetch resurfaced the same alert; B-080).
final _dismissedAlertsProvider = StateProvider<Set<String>>((ref) => {});

/// B-060: a prominent, dismissible banner for the newest unread ALERT (التنبيهات),
/// shown above the app body on every signed-in screen. Dismiss marks it read; the
/// next unread alert (if any) then surfaces. Notifications (non-ALERT) stay in the
/// inbox and never appear here.
class AlertBanner extends ConsumerWidget {
  const AlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(_dismissedAlertsProvider);
    final alerts = (ref.watch(unreadAlertsProvider).valueOrNull ?? const [])
        .where((a) => !dismissed.contains(a.id))
        .toList();
    if (alerts.isEmpty) return const SizedBox.shrink();
    final alert = alerts.first;

    Future<void> dismiss() async {
      // Hide locally first so the banner goes even if the server write can't reach.
      ref.read(_dismissedAlertsProvider.notifier).update((s) => {...s, alert.id});
      try {
        await NotificationRepository(ref.read(apiClientProvider)).markRead(alert.id);
      } catch (_) {}
      ref.invalidate(unreadAlertsProvider);
      ref.invalidate(notificationsUnreadCountProvider);
    }

    return Material(
      color: IntesharColors.oxblood,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (alert.title.isNotEmpty)
                  Text(alert.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.sans(14, color: Colors.white, w: FontWeight.w800)),
                Text(alert.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(12, color: Colors.white.withValues(alpha: 0.92))),
                if (alerts.length > 1)
                  Text('+${alerts.length - 1}',
                      style: IntesharType.mono(11, color: Colors.white.withValues(alpha: 0.7))),
              ]),
            ),
            IconButton(
              onPressed: dismiss,
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            ),
          ]),
        ),
      ),
    );
  }
}
