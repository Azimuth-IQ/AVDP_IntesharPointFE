import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ticks whenever the API layer detects the session is no longer valid — a 401,
/// including the backend's `SESSION_SUPERSEDED` (signed in elsewhere / logged out /
/// expired). The auth controller watches this and rebuilds; since the token has
/// already been cleared, it resolves to unauthenticated and the router bounces the
/// user to /login, instead of leaving them on a dead screen firing failing requests.
final sessionInvalidationProvider = StateProvider<int>((ref) => 0);
