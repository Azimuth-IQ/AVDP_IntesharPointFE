import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/connectivity.dart';
import 'package:inteshar/shared/widgets/min_tap_target.dart';

/// UX-79 — a persistent strip across the top of the app whenever the server is
/// unreachable.
///
/// Mounted as a **gate above the router** (see `app.dart`) rather than inside
/// `AppShell`, because `/pos/home` — the till, the one screen where a dead link
/// costs a customer at the counter — sits *outside* the shell route. The gate
/// covers every route: POS, login, and the shell alike.
///
/// The signal comes from [connectivityProvider]; the strip is purely its
/// read-out. It never appears while requests are succeeding — any HTTP response
/// of any status clears it immediately.
class ConnectivityGate extends ConsumerWidget {
  final Widget child;
  const ConnectivityGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(connectivityProvider).offline;
    if (!offline) return child;
    return Column(
      children: [
        const OfflineStrip(),
        // The strip has taken the top inset; without this the Scaffold below
        // would reserve the status-bar height a second time.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The strip itself. Rendered by [ConnectivityGate]; public so a screen that
/// wants it inline (a full-screen flow with its own chrome) can place one.
class OfflineStrip extends ConsumerWidget {
  const OfflineStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    // Ink bar, not the alert red — the ALERT banner directly below it owns red,
    // and this is an operational status, not a message from HQ. Same pairing the
    // snackbar theme uses, so it reads as a system strip in both modes.
    final bg = cs.onSurface;
    final fg = cs.surface;

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, size: 20, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ar ? 'لا يوجد اتصال بالخادم' : 'No connection to the server',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.sans(13.5, color: fg, w: FontWeight.w800),
                    ),
                    Text(
                      ar
                          ? 'لا تُتمّ عملية بيع حتى يعود الاتصال.'
                          : "Don't complete a sale until the link is back.",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.sans(
                        12.5,
                        color: fg.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MinTapTarget(
                minSize: const Size(48, 48),
                child: TextButton(
                  onPressed: () =>
                      ref.read(connectivityProvider.notifier).checkNow(),
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    textStyle: IntesharType.sans(13, w: FontWeight.w700),
                  ),
                  child: Text(ar ? 'إعادة المحاولة' : 'Retry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
