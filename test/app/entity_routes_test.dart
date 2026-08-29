// UX-15 — what happened to the retired entity surfaces, made enforceable.
//
// `/hq/main-agents` and `/hq/sub-agents` were the same rows as `/hq/entities`
// behind a type filter, with a different (and smaller) set of powers. They are
// gone as pages. They are NOT gone as URLs: three months of admin bookmarks, the
// links in older notification copy and the client's own written instructions all
// name them, and a 404 there reads as "the feature was removed".
//
// `/agent2/entities/:id/inventory` is the opposite case — a route that could
// never be reached. The drill-in requires an inventory-backed ROW, which under
// draw-on-print is HQ or a Main Agent only, and everything inside a Sub Agent's
// subtree is an AGENT2 or a STORE. It is deleted outright, with nothing to
// redirect, because nothing ever linked to it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/entity_directory_page.dart';

class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

void main() {
  /// One router per test. Building it also builds every GoRoute, so it is
  /// deliberately not rebuilt per lookup.
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

  GoRoute? routeAt(GoRouter router, String path) {
    for (final r in allRoutes(router.configuration.routes).whereType<GoRoute>()) {
      if (r.path == path) return r;
    }
    return null;
  }

  test('the retired tier directories still resolve, as redirects', () {
    final router = buildRouter();
    for (final path in ['/hq/main-agents', '/hq/sub-agents']) {
      final r = routeAt(router, path);
      expect(r, isNotNull,
          reason: '$path is a live bookmark; deleting it outright 404s an admin '
              'who has been using it for months');
      expect(r!.builder, isNull,
          reason: '$path must not build a page of its own again — a second '
              'directory over the same objects is exactly what UX-15 removed');
      expect(r.redirect, isNotNull, reason: '$path must redirect');
    }
  });

  test('the surviving directory is mounted for every tier that has a network',
      () {
    final router = buildRouter();
    for (final path in ['/hq/entities', '/agent1/entities', '/agent2/entities']) {
      final r = routeAt(router, path);
      expect(r, isNotNull, reason: '$path is the one entity directory');
      expect(r!.builder, isNotNull);
    }
  });

  test('the unreachable Sub-Agent stock drill-in is gone', () {
    final router = buildRouter();
    expect(routeAt(router, '/agent2/entities/:id/inventory'), isNull,
        reason: 'a Sub Agent has no inventory-backed descendants, so this route '
            'could never be entered — see the AGENT2 case in '
            'entity_directory_capability_test');
    // The two tiers that CAN drill in keep theirs.
    expect(routeAt(router, '/hq/entities/:id/inventory'), isNotNull);
    expect(routeAt(router, '/agent1/entities/:id/inventory'), isNotNull);
  });

  testWidgets('a bookmarked /hq/main-agents lands on the directory with that '
      'tier preselected', (tester) async {
    final router = buildRouter();
    final context = await _aContext(tester);

    // The real redirect callbacks, invoked with a real state…
    final redirects = <String, String?>{};
    for (final from in ['/hq/main-agents', '/hq/sub-agents']) {
      final route = routeAt(router, from)!;
      redirects[from] =
          await route.redirect!(context, _stateFor(router, from));
    }
    expect(redirects['/hq/main-agents'], '/hq/entities?type=AGENT1');
    expect(redirects['/hq/sub-agents'], '/hq/entities?type=AGENT2');

    // …and the other end of the handshake: the directory's builder has to turn
    // that query parameter back into a preselected tier, or the redirect lands
    // on an unfiltered list and the bookmark quietly stops meaning anything.
    final directory = routeAt(router, '/hq/entities')!;
    EntityDirectoryPage built(String location) => directory.builder!(
        context, _stateFor(router, location)) as EntityDirectoryPage;

    expect(built(redirects['/hq/main-agents']!).initialType, EntityType.AGENT1);
    expect(built(redirects['/hq/sub-agents']!).initialType, EntityType.AGENT2);
    expect(built('/hq/entities').initialType, isNull);
    expect(built('/hq/entities?type=NOT_A_TIER').initialType, isNull,
        reason: 'a stale bookmark should land on the whole directory, not crash');

    // Constructing a GoRouter schedules work of its own. Disposed HERE rather
    // than in a tearDown, which runs after the binding's pending-timer check and
    // would fail a test that has already passed.
    router.dispose();
    await tester.pumpAndSettle();
  });
}

/// A [GoRouterState] for [location], good enough to drive a redirect or a
/// builder that only reads the URI.
GoRouterState _stateFor(GoRouter router, String location) {
  final uri = Uri.parse(location);
  return GoRouterState(
    router.configuration,
    uri: uri,
    matchedLocation: uri.path,
    fullPath: uri.path,
    pathParameters: const {},
    pageKey: ValueKey(location),
  );
}

/// Any live BuildContext — the redirect and builder signatures take one.
Future<BuildContext> _aContext(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(Builder(builder: (c) {
    ctx = c;
    return const SizedBox.shrink();
  }));
  return ctx;
}
