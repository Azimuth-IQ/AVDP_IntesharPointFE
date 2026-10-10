import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/notifications/application/notification_provider.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';

/// Alerts dismissed this session — so a dismiss sticks even when the markRead call
/// fails offline (otherwise the refetch resurfaced the same alert; B-080).
///
/// Scoped to the signed-in identity: a second operator signing in on the same till
/// must see their own unread alerts, not have them hidden by the first operator's
/// dismissals (read receipts are per user on the server too).
final _dismissedAlertsProvider = StateProvider<Set<String>>((ref) {
  ref.watch(authStateProvider.select((s) {
    final a = s.valueOrNull;
    return a is AuthAuthenticated ? '${a.entity.id}|${a.role.name}|${a.isPosUser}' : '';
  }));
  return {};
});

/// Every alert in [alerts] that carries the same message as [alert].
///
/// The same alert is routinely sent more than once — re-sent to make sure it
/// landed, or while testing. The banner shows the newest and counts the rest, so
/// dismissing ONE copy surfaced the next, word-for-word identical copy in exactly
/// the same place: from the counter the X looked dead. All copies go together.
List<AppNotification> sameMessage(List<AppNotification> alerts, AppNotification alert) => [
      for (final a in alerts)
        if (a.title.trim() == alert.title.trim() && a.body.trim() == alert.body.trim()) a,
    ];

/// B-060: a prominent, dismissible banner for the newest unread ALERT (التنبيهات),
/// shown above the app body on every signed-in screen. Dismiss marks it read; the
/// next unread alert (if any) then surfaces. Notifications (non-ALERT) stay in the
/// inbox and never appear here.
class AlertBanner extends ConsumerWidget {
  const AlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(_dismissedAlertsProvider);
    final alerts = (ref.watch(unreadAlertsProvider).valueOrNull ?? const <AppNotification>[])
        .where((a) => !dismissed.contains(a.id))
        .toList();
    // The banner animates in, out, and between alerts, so a tap on the X always
    // visibly does something — even when another alert takes the dismissed one's
    // place. Instant when the platform asks for reduced motion.
    final motion = MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return AnimatedSize(
      duration: motion,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: motion,
        child: alerts.isEmpty
            ? const SizedBox(key: ValueKey('no-alert'), width: double.infinity)
            : _banner(context, ref, alerts),
      ),
    );
  }

  Widget _banner(BuildContext context, WidgetRef ref, List<AppNotification> alerts) {
    final alert = alerts.first;
    final copies = sameMessage(alerts, alert);
    final others = alerts.length - copies.length;

    Future<void> dismiss() async {
      // Hide locally first so the banner goes even if the server write can't reach.
      ref.read(_dismissedAlertsProvider.notifier)
          .update((s) => {...s, for (final a in copies) a.id});
      final repo = ref.read(notificationRepositoryProvider);
      await Future.wait([
        for (final a in copies) repo.markRead(a.id).catchError((_) {}),
      ]);
      ref.invalidate(inboxHeadProvider);
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
      // One identity per alert, so the switcher animates a change of alert.
      key: ValueKey(alert.id),
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
                // Distinct alerts still waiting — copies of this one leave with it.
                if (others > 0)
                  Text('+$others',
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
