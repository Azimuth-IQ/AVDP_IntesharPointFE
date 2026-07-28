import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_scaffold.dart';

/// Auth controller stub returning a fixed signed-in state, so [AppShell] can
/// resolve a role and render its navigation without touching the network.
class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

Entity _entity(EntityType type) =>
    Entity(id: 'e', meta: const EntityMeta(name: 'Inteshar Point'), type: type);

Future<void> _pumpShell(WidgetTester tester, EntityType type) async {
  // Force a narrow phone viewport so AppShell picks its mobile layout.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AuthAuthenticated(entity: _entity(type), role: UserRole.ADMIN);
  final router = GoRouter(
    initialLocation: '/hq/home',
    routes: [
      // One param route absorbs every /hq/* destination tap without a real page.
      GoRoute(
        path: '/hq/:section',
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
  testWidgets('HQ mobile bottom bar caps at 5 tabs and hides overflow', (tester) async {
    await _pumpShell(tester, EntityType.INTESHAR);

    expect(find.byType(NavigationBar), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 5, reason: 'HQ has 7 routes → 4 primary + More');

    // Primary four are present; the three setup routes are NOT on the bar.
    // (HQ home/index-0 is the System Activity oversight screen, not a dashboard.)
    // B-112: Reports holds the 4th slot, not Print Ops. A platform admin opens
    // Reports daily; Print Ops is an investigation tool for when something looks
    // wrong, so it sits one tap deeper.
    for (final label in ['System Activity', 'Hierarchy', 'Inventory', 'Reports', 'More']) {
      expect(find.text(label), findsWidgets, reason: '$label should be on the bar');
    }
    for (final hidden in ['Catalog', 'Templates', 'Batch Add', 'Print Ops']) {
      expect(find.text(hidden), findsNothing, reason: '$hidden belongs in the More sheet');
    }
  });

  testWidgets('Tapping More reveals the overflow destinations in a sheet', (tester) async {
    await _pumpShell(tester, EntityType.INTESHAR);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Templates'), findsOneWidget);
    expect(find.text('Batch Add'), findsOneWidget);
    expect(find.text('Print Ops'), findsOneWidget, reason: 'demoted, not deleted');

    // B-112 (retracted finding): the overflow is NOT a flat list — it carries the
    // same bilingual section headers as the desktop sidebar. Pin that, because I
    // nearly "fixed" a problem that did not exist.
    expect(find.text('CATALOG'), findsOneWidget, reason: 'More sheet must stay grouped');
    expect(find.text('ADMINISTRATION'), findsOneWidget);
  });

  testWidgets('Store role (4 routes) shows all tabs without a More overflow', (tester) async {
    await _pumpShell(tester, EntityType.STORE);

    // STORE has 4 destinations (Dashboard, Reports, POS points, Notifications) after the
    // legacy voucher pages (Inventory / Transactions) were removed — under the 5-tab cap,
    // so every destination sits on the bar and no "More" overflow is needed.
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 4);
    expect(find.text('More'), findsNothing);
  });
}
