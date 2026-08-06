import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/chat/data/chat_repository.dart';

/// B-133: total unread chat messages for the signed-in entity.
///
/// The tab gave no sign that a reply had arrived, so a shop only discovered an
/// answer by opening التواصل on the off-chance. The backend already returns a
/// per-thread `unread`; nothing consumed it.
///
/// Mirrors [notificationsUnreadCountProvider]: autoDispose, and it swallows
/// errors to 0 rather than surfacing them — a badge is an ambient hint, and a
/// failed count must never break the navigation it decorates. Invalidated by the
/// push listener so a live message lights the tab without a reload.
final chatUnreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final threads = await ChatRepository(api).threads();
    return threads.fold<int>(0, (sum, t) => sum + t.unread);
  } catch (_) {
    return 0;
  }
});
