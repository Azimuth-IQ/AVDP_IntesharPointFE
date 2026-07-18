// Role-based navigation gating for the Main-Agent (AGENT1) vs Sub-Agent (AGENT2)
// tiers. The existing mobile_nav_test already covers HQ (overflow) and STORE
// (4 tabs); this file pins the per-tier RBAC distinction that is easy to regress:
//
//   * AGENT1 exposes the Pricing ("Prices") destination (cap MANAGE_PRICING).
//   * AGENT2 must NOT expose Pricing anywhere — not even in the More sheet.
//   * Neither agent tier sees HQ-only sections (Companies/Catalog/Templates).
//
// Both agent tiers have >5 destinations, so the phone bar shows 4 primaries
// + a "More" overflow. AGENT1's primaries are Dashboard, Transactions,
// Inventory, Children; AGENT2 has NO Inventory (draw-on-print, B-042), so its
// primaries are Dashboard, Transactions, Children, Reports.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_scaffold.dart';

class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

Entity _entity(EntityType type) =>
    Entity(id: 'e', meta: const EntityMeta(name: 'Inteshar Point'), type: type);

Future<void> _pumpShell(WidgetTester tester, EntityType type, String prefix) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AuthAuthenticated(entity: _entity(type), role: UserRole.ADMIN);
  final router = GoRouter(
    initialLocation: '/$prefix/home',
    routes: [
      // A 2-segment route absorbs every /<prefix>/<section> destination tap.
      GoRoute(
        path: '/:prefix/:section',
        builder: (_, _) => const AppShell(child: SizedBox.shrink()),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith(() => _StubAuth(state))],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AGENT1 bar: 4 primaries + More; Prices lives in the More sheet', (tester) async {
    await _pumpShell(tester, EntityType.AGENT1, 'agent1');

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 5,
        reason: 'AGENT1 has >5 destinations → 4 primary + More');

    for (final label in ['Dashboard', 'Transactions', 'Inventory', 'Children', 'More']) {
      expect(find.text(label), findsWidgets, reason: '$label should be on the bar');
    }
    // HQ-only sections never appear for an agent.
    for (final hidden in ['Companies', 'Catalog', 'Templates']) {
      expect(find.text(hidden), findsNothing, reason: '$hidden is HQ-only');
    }

    // Pricing is AGENT1's privilege — it overflows into the More sheet.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Prices'), findsOneWidget, reason: 'AGENT1 has the Pricing screen');
    expect(find.text('Stores'), findsOneWidget);
  });

  testWidgets('AGENT2 bar: no Inventory (draw-on-print); NO Prices anywhere', (tester) async {
    await _pumpShell(tester, EntityType.AGENT2, 'agent2');

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 5,
        reason: 'AGENT2 has >5 destinations → 4 primary + More');

    // B-042: a Sub-Agent holds no stock (it draws from its parent's pool at
    // print time), so — unlike AGENT1 — it has NO Inventory destination.
    for (final label in ['Dashboard', 'Transactions', 'Children', 'More']) {
      expect(find.text(label), findsWidgets, reason: '$label should be on the bar');
    }
    expect(find.text('Inventory'), findsNothing, reason: 'AGENT2 has no inventory (B-042)');
    expect(find.text('Companies'), findsNothing, reason: 'Companies is HQ-only');

    // The RBAC line that matters: AGENT2 must NOT have Pricing, even in overflow.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Prices'), findsNothing, reason: 'Pricing is AGENT1-only');
    expect(find.text('Inventory'), findsNothing, reason: 'no inventory in the overflow either');
    expect(find.text('Stores'), findsOneWidget);
  });
}
