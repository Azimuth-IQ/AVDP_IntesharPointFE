import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// UX-159 — the app's freshness contract, made enforceable.
///
/// Cross-screen there is no cache invalidation anywhere except the unread-count
/// providers. Every other screen is fresh for exactly one reason: the signed-in
/// shell is a plain [ShellRoute], so navigating to a screen BUILDS it and
/// `initState` re-runs its load.
///
/// That is load-bearing and was undocumented. `StatefulShellRoute.indexedStack`
/// is the obvious upgrade for anyone asked to "keep scroll position" or "make
/// nav feel faster" — and it keeps every branch alive, so the load stops
/// re-running and the whole app quietly serves stale data. The client has
/// already reported this class of bug once ("لوحة التحكم / مجاي تحدث من تحذف شي"
/// — the panel doesn't update when you delete something), which was UX-155/157/158.
///
/// So this test does not describe the current design; it guards the assumption
/// the current design depends on. If you deliberately introduce a keep-alive,
/// this failing is the reminder that every screen's refresh has to be made
/// explicit FIRST.
class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

void main() {
  GoRouter buildRouter() {
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith(() => _StubAuth(AuthAuthenticated(
            entity: Entity(
              id: 'e',
              meta: const EntityMeta(name: 'Inteshar Point'),
              type: EntityType.INTESHAR,
            ),
            role: UserRole.ADMIN,
          ))),
    ]);
    addTearDown(container.dispose);
    return container.read(routerProvider);
  }

  /// Every route in the tree, flattened.
  List<RouteBase> allRoutes(List<RouteBase> roots) {
    final out = <RouteBase>[];
    void walk(List<RouteBase> rs) {
      for (final r in rs) {
        out.add(r);
        walk(r.routes);
      }
    }
    walk(roots);
    return out;
  }

  test('the signed-in shell keeps no branch alive', () {
    final routes = allRoutes(buildRouter().configuration.routes);

    final stateful = routes.whereType<StatefulShellRoute>().toList();
    expect(
      stateful,
      isEmpty,
      reason: 'A StatefulShellRoute keeps every branch alive, so a screen is no '
          'longer rebuilt on navigation and its initState load stops running. '
          'Nothing else in this app invalidates cross-screen data, so adopting '
          'one makes the entire app serve stale reads. Give every screen an '
          'explicit refresh before you land this.',
    );
  });

  test('there is still exactly one shell wrapping the signed-in routes', () {
    // If this becomes 0 the guard above stops meaning anything, because there
    // would be no shell left to accidentally make stateful.
    final routes = allRoutes(buildRouter().configuration.routes);
    expect(routes.whereType<ShellRoute>().length, 1);
  });

  test('the shell hosts many routes, so the guard covers the app', () {
    // Guards against the shell being quietly reduced to a couple of screens
    // while the rest move somewhere unprotected.
    final shell =
        allRoutes(buildRouter().configuration.routes).whereType<ShellRoute>().single;
    expect(shell.routes.length, greaterThan(15),
        reason: 'the signed-in surface should live under the guarded shell');
  });
}
