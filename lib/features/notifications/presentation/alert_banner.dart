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

    // UX-154: the banner used to fade its own text — body at white 92%
    // (**4.27:1** on the oxblood fill) and the "+N" counter at 70% (**2.98:1**),
    // both under the 4.5:1 body floor, on the one surface in the app that only
    // appears when something is wrong.
    //
    // The fill is the constraint, not the alpha: full white on #DC2626 measures
    // **4.83:1**, so there is exactly one passing value and every step down from
    // it fails. The alphas therefore go entirely and the hierarchy comes from
    // size and weight — which is what it should have been on a saturated fill.
    // The fill itself stays: 4.83:1 clears AA for body, and darkening the red
    // would cost the "stop" read that is the whole point of this banner.
    const fill = IntesharColors.oxblood;
    // White measures 4.83:1 here; ink is only 3.68:1, so `legibleOn` picks white.
    final onFill = legibleOn(fill);
    return Material(
      color: fill,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              IntesharSpacing.lg, IntesharSpacing.sm2, IntesharSpacing.sm, IntesharSpacing.sm2),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: onFill, size: 20),
            const SizedBox(width: IntesharSpacing.sm2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (alert.title.isNotEmpty)
                  Text(alert.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharText.bodyLg(color: onFill, w: IntesharWeight.heavy)),
                Text(alert.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharText.body(color: onFill)),
                if (alerts.length > 1)
                  Text('+${alerts.length - 1}',
                      style: IntesharType.mono(IntesharScale.caption,
                          color: onFill, w: IntesharWeight.bold)),
              ]),
            ),
            IconButton(
              onPressed: dismiss,
              icon: Icon(Icons.close, color: onFill, size: 18),
              tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            ),
          ]),
        ),
      ),
    );
  }
}
