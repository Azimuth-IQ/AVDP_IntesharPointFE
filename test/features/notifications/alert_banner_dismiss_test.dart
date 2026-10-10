// The top-of-screen ALERT banner's X (reported 2026-10-10 as "does not work").
//
// Reproduced against a local stack, the X itself did work: the alert was marked read
// and the next one surfaced. What made it LOOK dead was the next one being the same
// message — alerts get re-sent — appearing in exactly the same place. These pin the
// behaviour the operator actually sees: one tap clears that message, every copy of it,
// and the banner visibly changes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/notifications/application/notification_provider.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';
import 'package:inteshar/features/notifications/presentation/alert_banner.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_scaffold.dart';

/// An inbox the test controls, which remembers what was marked read — the same
/// per-user receipt the server keeps.
class _FakeInbox implements NotificationRepository {
  _FakeInbox(this.items);
  List<AppNotification> items;
  final read = <String>[];
  /// Models a dismissal made offline: the write never reaches the server.
  bool markReadFails = false;

  @override
  Future<Paged<AppNotification>> inbox({int page = 0, int size = 30}) async =>
      Paged(items: [for (final n in items) n.copyWith(isRead: read.contains(n.id))], page: page, size: size, hasMore: false);

  @override
  Future<void> markRead(String id) async {
    if (markReadFails) throw StateError('offline');
    read.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
  void become(AuthState next) => state = AsyncData(next);
}

AuthAuthenticated _signedIn(String entityId, {UserRole role = UserRole.ADMIN}) => AuthAuthenticated(
      entity: Entity(id: entityId, meta: const EntityMeta(name: 'Shop'), type: EntityType.STORE),
      role: role,
    );

AppNotification _alert(String id, String title, String body) =>
    AppNotification(id: id, title: title, body: body, type: 'ALERT');

Future<_FakeInbox> _pumpBanner(WidgetTester tester, List<AppNotification> items, {AuthState? auth}) async {
  final inbox = _FakeInbox(items);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _StubAuth(auth ?? _signedIn('shop-1'))),
      notificationRepositoryProvider.overrideWithValue(inbox),
    ],
    child: const MaterialApp(home: Scaffold(body: Column(children: [AlertBanner()]))),
  ));
  await tester.pumpAndSettle();
  return inbox;
}

void main() {
  testWidgets('in the real shell on a phone, the X clears the alert and marks it read', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final inbox = _FakeInbox([_alert('a1', 'Stop selling', 'Card X is recalled')]);
    final router = GoRouter(
      initialLocation: '/store/home',
      routes: [GoRoute(path: '/:prefix/:section', builder: (_, _) => const AppShell(child: SizedBox.shrink()))],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith(() => _StubAuth(_signedIn('shop-1'))),
        notificationRepositoryProvider.overrideWithValue(inbox),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Stop selling'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Stop selling'), findsNothing);
    expect(inbox.read, ['a1']);
  });

  testWidgets('copies of the same message leave together, so the X never looks dead', (tester) async {
    final inbox = await _pumpBanner(tester, [
      _alert('c3', 'Stop selling', 'Card X is recalled'),
      _alert('c2', 'Stop selling', 'Card X is recalled'),
      _alert('c1', 'Stop selling', 'Card X is recalled'),
      _alert('o1', 'Price change', 'Zain 5000 is now 5250'),
    ]);
    // Three copies of one message plus one other: the counter names the OTHER one.
    expect(find.text('Stop selling'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Stop selling'), findsNothing);
    expect(find.text('Price change'), findsOneWidget);
    expect(inbox.read, unorderedEquals(['c3', 'c2', 'c1']));
  });

  testWidgets('the last alert dismissed leaves no banner behind', (tester) async {
    await _pumpBanner(tester, [_alert('a1', 'Stop selling', 'Card X is recalled')]);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets("another operator signing in on the same till sees their own alerts", (tester) async {
    final inbox = await _pumpBanner(tester, [_alert('a1', 'Stop selling', 'Card X is recalled')]);
    // The first operator dismisses — and, offline, the server never hears of it.
    inbox.markReadFails = true;
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Stop selling'), findsNothing);

    // A different operator signs in; nothing was marked read for them.
    final container = ProviderScope.containerOf(tester.element(find.byType(AlertBanner)));
    (container.read(authStateProvider.notifier) as _StubAuth).become(_signedIn('shop-1', role: UserRole.USER));
    container.invalidate(inboxHeadProvider);
    await tester.pumpAndSettle();

    expect(find.text('Stop selling'), findsOneWidget);
  });
}
