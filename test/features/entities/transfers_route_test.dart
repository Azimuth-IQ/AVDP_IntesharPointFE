import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// B-111: the dashboard's Transfer button now navigates to the ONE transfer
/// flow instead of opening a second, older sheet. That only works if every tier
/// that can transfer has a route, and every tier that cannot returns null —
/// otherwise the button either dead-ends or disappears where it is needed.
void main() {
  test('agent tiers have a transfers page', () {
    expect(EntityType.AGENT1.transfersRoute, '/agent1/transfers');
    expect(EntityType.AGENT2.transfersRoute, '/agent2/transfers');
  });

  test('HQ and Store have none, and that is deliberate', () {
    // HQ pushes value by assigning stock (batch add → uploaded-value counter);
    // a Store has no children to send to. The dashboard hides the button for both.
    expect(EntityType.INTESHAR.transfersRoute, isNull);
    expect(EntityType.STORE.transfersRoute, isNull);
  });

  test('every route points at that tier\'s own shell', () {
    for (final t in EntityType.values) {
      final r = t.transfersRoute;
      if (r == null) continue;
      final prefix = t.homeRoute.split('/')[1];
      expect(r.startsWith('/$prefix/'), isTrue,
          reason: '$t would navigate outside its shell and be bounced: $r');
    }
  });
}
