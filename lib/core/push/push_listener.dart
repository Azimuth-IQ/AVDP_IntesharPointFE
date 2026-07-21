import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/push/push_subscriber.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/notifications/application/notification_provider.dart';

/// B-061: keeps a single [PushSubscriber] alive for the signed-in session. On a
/// ping it refreshes the alert banner + notification badge (chat screens keep
/// their own short poll). Placed high in the widget tree so it lives for the
/// whole app; renders its [child] unchanged.
class PushListener extends ConsumerStatefulWidget {
  const PushListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PushListener> createState() => _PushListenerState();
}

class _PushListenerState extends ConsumerState<PushListener> {
  PushSubscriber? _sub;
  String _activeTopic = '';

  void _sync(AuthState? auth) {
    final token = auth is AuthAuthenticated ? auth.entity.pushToken : '';
    final base = auth is AuthAuthenticated ? auth.entity.pushBaseUrl : '';
    // Same topic already running → nothing to do.
    if (token == _activeTopic && (_sub != null || token.isEmpty)) return;
    _sub?.stop();
    _sub = null;
    _activeTopic = token;
    if (token.isEmpty || base.isEmpty) return;
    _sub = PushSubscriber(
      baseUrl: base,
      topic: token,
      onPing: (_) {
        // Refresh the providers the shell watches. Cheap; deduped by autoDispose.
        ref.invalidate(unreadAlertsProvider);
        ref.invalidate(notificationsUnreadCountProvider);
      },
    )..start();
  }

  @override
  void dispose() {
    _sub?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // React to login/logout + topic changes.
    ref.listen(authStateProvider, (_, next) => _sync(next.valueOrNull));
    // Ensure the subscriber is (re)started on first build after a hot restart.
    _sync(ref.read(authStateProvider).valueOrNull);
    return widget.child;
  }
}
