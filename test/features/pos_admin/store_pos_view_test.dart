// What the نقاط البيع section does for a STORE-tier owner.
//
// A store IS a POS point, so the agent body of PosAdminPage was structurally
// wrong for it: `/pos-users/list/page` returns the host's STORE *children* and
// nothing can create a store under a store, so the list was always empty under
// a permanent 0/0/0 quota — with a disabled "Onboard POS" button and a red
// "ask headquarters to grant more" line telling the shop owner to chase points
// the server would refuse to let them spend (`onboard` 400s on a non-agent
// host). These pin the honest replacement.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos_admin/domain/pos_roles.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_admin_page.dart';
import 'package:inteshar/features/pos_admin/presentation/store_pos_view.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

Entity _store({List<EntityUser> users = const [], bool active = true}) => Entity(
      id: 'store-1',
      meta: const EntityMeta(name: 'Saad Shop', governorates: ['BAGHDAD']),
      profile: const EntityProfile(ownerName: 'Saad Ali', address: 'Karrada, near the bridge'),
      parent: 'agent2-1',
      type: EntityType.STORE,
      users: users,
      active: active,
    );

const _counter = EntityUser(id: 'pos-1', phone: '07704444444', role: UserRole.USER, isPos: true);
const _owner = EntityUser(id: 'u-1', phone: '07703333333', role: UserRole.ADMIN);

Future<void> _pump(WidgetTester tester, Entity entity) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          () => _StubAuth(AuthAuthenticated(entity: entity, role: UserRole.ADMIN)),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PosAdminPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('counterUserOf', () {
    test('prefers the isPos operator over the ADMIN owner', () {
      expect(counterUserOf(_store(users: [_owner, _counter]))?.phone, _counter.phone);
    });

    test('falls back to a USER-role login on pre-isPos shops', () {
      const legacy = EntityUser(id: 'u-2', phone: '07705555555', role: UserRole.USER);
      expect(counterUserOf(_store(users: [_owner, legacy]))?.phone, legacy.phone);
    });

    test('returns null when the shop only has its ADMIN owner', () {
      // The credential endpoints all require isPos, so returning the owner here
      // would offer buttons that are guaranteed to 403.
      expect(counterUserOf(_store(users: [_owner])), isNull);
    });

    test('returns null on a shop with no logins at all', () {
      expect(counterUserOf(_store()), isNull);
    });
  });

  test('only agents can hold POS points — never HQ or a store', () {
    // A point granted to a store can never be spent (the server refuses to
    // onboard under one) yet still counts as "issued" in the network KPIs.
    expect(kPosPointHolderTypes, [EntityType.AGENT1, EntityType.AGENT2]);
    expect(kPosPointHolderTypes, isNot(contains(EntityType.STORE)));
    expect(kPosPointHolderTypes, isNot(contains(EntityType.INTESHAR)));
  });

  testWidgets('STORE gets its own POS view, not the agent quota body', (tester) async {
    await _pump(tester, _store(users: [_owner, _counter]));

    expect(find.byType(StorePosView), findsOneWidget);
    // None of the agent affordances may appear: every one of them is either a
    // dead end or a server refusal for a store.
    for (final gone in [
      'Onboard POS',
      'Grant slots',
      'No POS users yet.',
      'No available POS points — ask headquarters to grant more.',
      'Total',
      'Available',
      'Revoke',
      'Deactivate',
    ]) {
      expect(find.text(gone), findsNothing, reason: '"$gone" is meaningless for a store');
    }
  });

  testWidgets('shows the shop identity and the counter login', (tester) async {
    await _pump(tester, _store(users: [_owner, _counter]));

    expect(find.text('Saad Shop'), findsOneWidget);
    expect(find.text('Saad Ali'), findsOneWidget);
    expect(find.text('Karrada, near the bridge'), findsOneWidget);
    // The COUNTER phone, not the signed-in owner's.
    expect(find.text('07704444444'), findsOneWidget);
    expect(find.text('07703333333'), findsNothing);
  });

  testWidgets('offers the credential resets that the server authorises for a store', (tester) async {
    await _pump(tester, _store(users: [_owner, _counter]));

    // reset-pin / reset-password / reset-totp are scoped self-or-descendant, and
    // a store's own operator is "self".
    for (final action in ['Reset PIN', 'Reset password', 'Reset 2FA']) {
      expect(find.widgetWithText(OutlinedButton, action), findsOneWidget);
    }
  });

  testWidgets('no counter login → explains instead of showing dead buttons', (tester) async {
    await _pump(tester, _store(users: [_owner]));

    expect(find.text('No counter login on this shop'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reset PIN'), findsNothing);
  });

  testWidgets('pre-isPos counter → resets hidden, reason given (they would 403)', (tester) async {
    const legacy = EntityUser(id: 'u-2', phone: '07705555555', role: UserRole.USER);
    await _pump(tester, _store(users: [_owner, legacy]));

    expect(find.text('07705555555'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reset PIN'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reset 2FA'), findsNothing);
  });

  testWidgets('a disabled shop says so', (tester) async {
    await _pump(tester, _store(users: [_owner, _counter], active: false));

    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('POS'), findsNothing);
  });
}
