import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

// Field test 2026-10-29: pages read the session as `valueOrNull as AuthAuthenticated?`.
// After sign-out the state is AuthUnauthenticated — not null — so the cast threw and
// every page still open crashed the web app as it rebuilt.
void main() {
  final session = AuthAuthenticated(
    entity: Entity(id: 'e', meta: const EntityMeta(name: 'Shop'), type: EntityType.STORE),
    role: UserRole.USER,
  );

  test('the old cast throws once signed out — the crash being fixed', () {
    final AsyncValue<AuthState> out = AsyncValue<AuthState>.data(AuthUnauthenticated());
    expect(() => out.valueOrNull as AuthAuthenticated?, throwsA(isA<TypeError>()));
    expect(out.signedIn, isNull);
  });

  test('signedIn is null in every state but signed in', () {
    expect(AsyncValue<AuthState>.data(AuthUnauthenticated()).signedIn, isNull);
    expect(AsyncValue<AuthState>.data(AuthLoading()).signedIn, isNull);
    expect(const AsyncValue<AuthState>.loading().signedIn, isNull);
    expect(AsyncValue<AuthState>.error('x', StackTrace.empty).signedIn, isNull);
  });

  test('signedIn returns the session when signed in', () {
    expect(AsyncValue<AuthState>.data(session).signedIn, same(session));
  });
}
