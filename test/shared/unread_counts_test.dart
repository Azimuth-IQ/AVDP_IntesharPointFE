import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/shared/widgets/app_scaffold.dart';

/// B-133/B-134: which destination a badge belongs to.
///
/// Keyed by route SUFFIX rather than by index, because the destination list is
/// filtered per role — `/hq/chat` sits at a different position than
/// `/agent2/chat`, so an index-based badge would decorate the wrong tab for
/// some tiers and look like a phantom unread.
void main() {
  const counts = UnreadCounts(notifications: 3, chat: 5);

  test('each destination gets its own count', () {
    expect(counts.forRoute('/hq/notifications'), 3);
    expect(counts.forRoute('/hq/chat'), 5);
  });

  test('the same suffix resolves across every tier', () {
    for (final tier in ['/hq', '/agent1', '/agent2', '/store']) {
      expect(counts.forRoute('$tier/chat'), 5, reason: tier);
      expect(counts.forRoute('$tier/notifications'), 3, reason: tier);
    }
  });

  test('destinations without an unread concept get nothing', () {
    for (final r in ['/hq/inventory', '/agent1/pricing', '/store/pos-users', '/pos']) {
      expect(counts.forRoute(r), 0, reason: r);
    }
  });

  test('a route merely CONTAINING chat does not badge', () {
    // Suffix, not substring: a future /hq/chat-settings must not inherit the
    // unread count of the real conversation list.
    expect(counts.forRoute('/hq/chat-settings'), 0);
    expect(counts.forRoute('/hq/notifications-compose'), 0);
  });

  group('the More overflow bubbles hidden counts', () {
    test('sums every badge-bearing route it hides', () {
      // Previously only notifications bubbled up, so an unread chat pushed into
      // the overflow showed nothing at all on a phone.
      expect(counts.forRoutes(['/hq/chat', '/hq/notifications']), 8);
    });

    test('ignores hidden routes that carry no count', () {
      expect(counts.forRoutes(['/hq/templates', '/hq/companies']), 0);
    });

    test('is zero when nothing is unread', () {
      const none = UnreadCounts();
      expect(none.forRoutes(['/hq/chat', '/hq/notifications']), 0);
    });
  });
}
