import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/core/api/session_invalidation.dart';

/// Shows a single friendly "session ended — sign in again" dialog when the API layer signals
/// an INVOLUNTARY session end (it ticks [sessionInvalidationProvider] on a 401 /
/// SESSION_SUPERSEDED / working-hours 403), instead of the app silently bouncing to `/login`.
/// A user-initiated logout does not tick the provider, so this never fires on a normal sign-out.
///
/// Mounted above the router (in the MaterialApp builder), so it pushes over any page via
/// [rootNavigatorKey].
class SessionExpiryGate extends ConsumerStatefulWidget {
  final Widget child;
  const SessionExpiryGate({super.key, required this.child});

  @override
  ConsumerState<SessionExpiryGate> createState() => _SessionExpiryGateState();
}

class _SessionExpiryGateState extends ConsumerState<SessionExpiryGate> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(sessionInvalidationProvider, (prev, next) {
      if ((prev ?? 0) < next) _prompt();
    });
    return widget.child;
  }

  Future<void> _prompt() async {
    if (_showing) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    _showing = true;
    final ar = Localizations.localeOf(ctx).languageCode == 'ar';
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        icon: const Icon(Icons.lock_clock_outlined, size: 30),
        title: Text(ar ? 'انتهت الجلسة' : 'Session ended'),
        content: Text(
          ar
              ? 'انتهت صلاحية جلستك أو تم تسجيل الدخول من جهاز آخر. الرجاء تسجيل الدخول من جديد.'
              : 'Your session has expired, or you signed in on another device. Please sign in again.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(routerProvider).go('/login');
            },
            icon: const Icon(Icons.login, size: 18),
            label: Text(ar ? 'تسجيل الدخول' : 'Sign in'),
          ),
        ],
      ),
    );
    _showing = false;
  }
}
