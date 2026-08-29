// UX-15 / UX-93 — the capability matrix the consolidation could silently break.
//
// HQ had three routes listing the same `Entity` objects: the hierarchy tree
// (`/hq/entities`), Main Agents (`/hq/main-agents`) and Sub Agents
// (`/hq/sub-agents`). The two tier pages are retired to redirects and the tree
// became a VIEW MODE of the surviving directory. The refactor's one real risk is
// that a power available on a retired surface is not available on the survivor,
// for some role — which is far worse than the inconsistency it replaced, because
// a missing action is invisible.
//
// So this file pins the union, not the implementation:
//
//   Part A  the canonical row action set, per (viewer role, viewer capability,
//           row tier). Every mutating action the retired pages offered came from
//           `EntityRowActionsButton`, so this IS their menu.
//   Part B  the surviving page: one search, both view modes over the same rows,
//           the type filter the retired pages were, and the CREATE action that
//           only they used to have.
//
// The matrix is written out longhand on purpose. Deriving it would just restate
// `availableActions`, and a test that recomputes the code passes whatever the
// code does.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/entity_directory_page.dart';
import 'package:inteshar/features/entities/presentation/entity_row_actions.dart';
import 'package:inteshar/l10n/app_localizations.dart';

// ── Auth stubs ────────────────────────────────────────────────────────────────

class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

/// A signed-in session. `effectiveCapabilities` is set (not `capabilities`)
/// because that is the server-resolved set `can()` treats as authoritative — the
/// ADMIN-role bypass would otherwise hand every scenario every capability and
/// the VIEW_REPORTS-supervisor case below would silently stop testing anything.
AuthAuthenticated _session(EntityType type, Set<Capability> caps) =>
    AuthAuthenticated(
      entity: Entity(
        id: 'viewer',
        meta: const EntityMeta(name: 'Viewer'),
        type: type,
      ),
      role: UserRole.ADMIN,
      effectiveCapabilities: caps,
    );

/// The tier pills an HQ viewer is offered, by key: the "All" pill plus one per
/// tier. Matching on the LABELS would be satisfied by the row subtitles, which
/// carry the same tier names.
const List<String> _pillKeys = [
  'entity-type-pill-ALL',
  'entity-type-pill-INTESHAR',
  'entity-type-pill-AGENT1',
  'entity-type-pill-AGENT2',
  'entity-type-pill-STORE',
];

EntitySummaryRow _row(EntityType type) => EntitySummaryRow(
      id: 'row-${type.name}',
      name: type.name,
      type: type,
      parentName: 'Parent',
      childrenCount: 2,
      productsCount: 40,
      userCount: 3,
      governorates: const ['BG'],
    );

// ── Part A: the canonical row action set ─────────────────────────────────────

/// The menu this viewer gets on each tier, with and without the "Open agent"
/// hop. Both variants come from ONE pump: `authStateProvider` resolves
/// asynchronously, so the first frame is still `AuthLoading` and every action
/// list would come back empty — pumping twice per scenario made that easy to
/// miss.
typedef _Matrix = ({
  Map<EntityType, List<EntityRowAction>> withOpen,
  Map<EntityType, List<EntityRowAction>> withoutOpen,
});

Future<_Matrix> _actionsFor(WidgetTester tester, AuthAuthenticated session) async {
  final withOpen = <EntityType, List<EntityRowAction>>{};
  final withoutOpen = <EntityType, List<EntityRowAction>>{};
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith(() => _StubAuth(session))],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            // `availableActions` READS the auth provider, so nothing here would
            // rebuild when the stub resolves and every list would be frozen at
            // its AuthLoading value — which still contains `open` (that item
            // depends on the row, not the viewer) and so would sail past a
            // non-empty guard. Watching is what makes the settled frame real.
            final resolved = ref.watch(authStateProvider).valueOrNull;
            if (resolved is! AuthAuthenticated) return const SizedBox.shrink();
            for (final t in EntityType.values) {
              withOpen[t] = availableActions(ref, _row(t));
              withoutOpen[t] = availableActions(ref, _row(t), showOpen: false);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Guard the guard: an unmeasured matrix would make every "isNot(contains(…))"
  // below pass vacuously.
  expect(withOpen.keys.toSet(), EntityType.values.toSet(),
      reason: 'the session never resolved — the matrix is measuring nothing');
  return (withOpen: withOpen, withoutOpen: withoutOpen);
}

void main() {
  group('Part A — one action set, whichever door you came in through', () {
    testWidgets('HQ with MANAGE_AGENTS keeps every power the tier pages had',
        (tester) async {
      final a = (await _actionsFor(
              tester, _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS})))
          .withOpen;

      // The platform root: editable and expandable, never deletable (an operator
      // cleared the tree bottom-up onto the root once and locked everyone out),
      // and "visible products" is meaningless on the account that owns them all.
      expect(a[EntityType.INTESHAR], [
        EntityRowAction.edit,
        EntityRowAction.manageUsers,
        EntityRowAction.viewInventory,
        EntityRowAction.addChild,
      ]);

      // A Main Agent — this is exactly what `/hq/main-agents` could do, plus the
      // manage-users / add-child / drill-in it could NOT.
      expect(a[EntityType.AGENT1], [
        EntityRowAction.open,
        EntityRowAction.edit,
        EntityRowAction.manageUsers,
        EntityRowAction.visibleProducts,
        EntityRowAction.viewInventory,
        EntityRowAction.addChild,
        EntityRowAction.delete,
      ]);

      // A Sub Agent holds no cards under draw-on-print, so there is no warehouse
      // to drill into, and a POS shop is onboarded through the quota screen
      // rather than as a tree child — hence no addChild.
      expect(a[EntityType.AGENT2], [
        EntityRowAction.open,
        EntityRowAction.edit,
        EntityRowAction.manageUsers,
        EntityRowAction.visibleProducts,
        EntityRowAction.delete,
      ]);

      // A shop has no agent page to open and no children.
      expect(a[EntityType.STORE], [
        EntityRowAction.edit,
        EntityRowAction.manageUsers,
        EntityRowAction.visibleProducts,
        EntityRowAction.delete,
      ]);
    });

    testWidgets('an HQ supervisor with only VIEW_REPORTS gets NO mutation',
        (tester) async {
      final a = (await _actionsFor(
              tester, _session(EntityType.INTESHAR, {Capability.VIEW_REPORTS})))
          .withOpen;

      for (final t in EntityType.values) {
        expect(a[t], isNot(contains(EntityRowAction.delete)),
            reason: 'delete is the most destructive action in the app and '
                'MANAGE_AGENTS is what gates it — reaching the directory on '
                'VIEW_REPORTS must not be a way round that');
        expect(a[t], isNot(contains(EntityRowAction.edit)));
        expect(a[t], isNot(contains(EntityRowAction.manageUsers)));
        expect(a[t], isNot(contains(EntityRowAction.visibleProducts)));
        expect(a[t], isNot(contains(EntityRowAction.addChild)));
      }
      // Read-only oversight still browses stock and opens an agent's page.
      expect(a[EntityType.AGENT1],
          [EntityRowAction.open, EntityRowAction.viewInventory]);
      expect(a[EntityType.STORE], isEmpty);
    });

    testWidgets('a Main Agent may browse downstream stock but never mutate',
        (tester) async {
      final a = (await _actionsFor(
              tester, _session(EntityType.AGENT1, {Capability.AGENT_ADMIN})))
          .withOpen;

      // AGENT_ADMIN is a wildcard capability, so this pins that entity CRUD is
      // gated on being HQ as well — which is what `CallerService` enforces.
      for (final t in EntityType.values) {
        expect(a[t], isNot(contains(EntityRowAction.edit)));
        expect(a[t], isNot(contains(EntityRowAction.delete)));
        expect(a[t], isNot(contains(EntityRowAction.addChild)));
      }
      expect(a[EntityType.AGENT1],
          [EntityRowAction.open, EntityRowAction.viewInventory]);
      expect(a[EntityType.AGENT2], [EntityRowAction.open]);
      expect(a[EntityType.STORE], isEmpty);
    });

    testWidgets('a Sub Agent is never offered a stock drill-in', (tester) async {
      final a = (await _actionsFor(
              tester, _session(EntityType.AGENT2, {Capability.AGENT_ADMIN})))
          .withOpen;

      // This is the dead `/agent2/entities/:id/inventory` route, pinned from the
      // other end: the drill-in needs an inventory-backed ROW, and everything in
      // a Sub Agent's subtree is an AGENT2 or a STORE. The route is gone and
      // `inventoryRoutePrefix` no longer names /agent2 — if either comes back
      // alone, one of these two halves breaks.
      for (final t in EntityType.values) {
        expect(a[t], isNot(contains(EntityRowAction.viewInventory)));
      }
      expect(a[EntityType.AGENT2], [EntityRowAction.open]);
      expect(a[EntityType.STORE], isEmpty);
    });

    testWidgets('showOpen:false drops only the hop, never a power',
        (tester) async {
      final m = await _actionsFor(
          tester, _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}));
      for (final t in EntityType.values) {
        expect(m.withoutOpen[t],
            m.withOpen[t]!.where((a) => a != EntityRowAction.open).toList(),
            reason: 'a surface that already opens the agent on tap suppresses '
                'the menu hop and nothing else');
      }
    });
  });

  // ── Part B: the surviving page ─────────────────────────────────────────────

  group('Part B — one directory, two views, one search', () {
    testWidgets('list mode is the default and carries the type filter the '
        'retired tier pages were', (tester) async {
      final api = _FakeApi();
      await _pumpDirectory(tester, api,
          session: _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}));

      expect(find.byType(TextField), findsOneWidget,
          reason: 'one search box, shared by both views');
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Tree'), findsOneWidget);
      // The pills the System Activity Entities tab had and the hierarchy did
      // not. Found by key, because the tier NAMES also appear as row subtitles —
      // matching on text would pass on a page with no pills at all.
      for (final k in _pillKeys) {
        expect(find.byKey(ValueKey(k)), findsOneWidget,
            reason: '$k is missing from the toolbar');
      }
      // Rows came from the ONE feed, not from a tree walk.
      expect(api.searchCalls, greaterThan(0));
      expect(api.childrenCalls, 0);
      expect(find.text('Baghdad Main'), findsOneWidget);
      expect(find.text('Karkh Sub'), findsOneWidget);
    });

    testWidgets('?type= preselects the tier, exactly as /hq/main-agents did',
        (tester) async {
      final api = _FakeApi();
      await _pumpDirectory(tester, api,
          session: _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}),
          initialType: EntityType.AGENT1);

      expect(api.lastSearchType, 'AGENT1',
          reason: 'the redirect from /hq/main-agents must reach the server as a '
              'tier filter, not just tint a pill');
      // …and the create button narrows to the tier being listed.
      expect(find.text('New Main Agent'), findsOneWidget);
      expect(find.text('New Sub Agent'), findsNothing);
    });

    testWidgets('creating an agent survives the retirement of the tier pages',
        (tester) async {
      await _pumpDirectory(tester, _FakeApi(),
          session: _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}));
      // Unfiltered, both tiers are offerable; the secondary may be behind the
      // header's overflow menu, so only the primary is asserted on screen.
      expect(find.text('New Main Agent'), findsOneWidget);
    });

    testWidgets('the create action is gated exactly where the server gates it',
        (tester) async {
      // HQ without MANAGE_AGENTS: reaches the directory (VIEW_REPORTS), must not
      // be offered a create the backend would refuse.
      await _pumpDirectory(tester, _FakeApi(),
          session: _session(EntityType.INTESHAR, {Capability.VIEW_REPORTS}));
      expect(find.textContaining('New '), findsNothing);

      // A Main Agent: entity create is HQ-only in `CallerService`, whatever
      // capabilities the agent holds.
      await _pumpDirectory(tester, _FakeApi(),
          session: _session(EntityType.AGENT1, {Capability.AGENT_ADMIN}));
      expect(find.textContaining('New '), findsNothing);
    });

    testWidgets('a Sub Agent is offered no tier it cannot see', (tester) async {
      await _pumpDirectory(tester, _FakeApi(),
          session: _session(EntityType.AGENT2, {Capability.AGENT_ADMIN}));
      // Its subtree holds only sub-agents and shops, so pills for the tiers
      // above would only ever return an empty list.
      expect(find.byKey(const ValueKey('entity-type-pill-INTESHAR')), findsNothing);
      expect(find.byKey(const ValueKey('entity-type-pill-AGENT1')), findsNothing);
      expect(find.byKey(const ValueKey('entity-type-pill-AGENT2')), findsOneWidget);
      expect(find.byKey(const ValueKey('entity-type-pill-STORE')), findsOneWidget);
    });

    testWidgets('the tree is a view mode of the same page, not another place',
        (tester) async {
      final api = _FakeApi();
      await _pumpDirectory(tester, api,
          session: _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}));

      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      expect(api.childrenCalls, greaterThan(0),
          reason: 'the tree still expands lazily, one node at a time (B-023)');
      expect(find.text('Baghdad Main'), findsOneWidget,
          reason: 'the same rows, arranged as the org chart');
      // The type pills belong to the list: filtering a hierarchy by tier cuts
      // branches out of the middle and leaves an org chart that lies.
      for (final k in _pillKeys) {
        expect(find.byKey(ValueKey(k)), findsNothing,
            reason: '$k must not be in tree mode');
      }
      // Still ONE search box — the page did not grow a second toolbar.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('typing moves the toggle to List rather than silently '
        'flattening the tree', (tester) async {
      final api = _FakeApi();
      await _pumpDirectory(tester, api,
          session: _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}));
      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'karkh');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(api.lastSearchQuery, 'karkh');
      // Back in list mode — which is visible, because the pills are.
      expect(find.byKey(const ValueKey('entity-type-pill-AGENT1')), findsOneWidget);
    });

    testWidgets('the onboarding strip the tier pages carried survives — for the '
        'viewer who could see it', (tester) async {
      // UX-02's "which agent has the fewest POS points?" was answerable only by
      // scanning `/hq/main-agents`. It is on the directory row now.
      await _pumpDirectory(tester, _FakeApi(),
          session: _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}));
      expect(find.byKey(const ValueKey('readiness-a1')), findsOneWidget);

      // But every chip in it opens an HQ route, and a Main Agent's OWN row is in
      // its own directory — so for that viewer the strip is three destinations
      // the role guard bounces them out of.
      await _pumpDirectory(tester, _FakeApi(),
          session: _session(EntityType.AGENT1, {Capability.AGENT_ADMIN}));
      expect(find.byKey(const ValueKey('readiness-a1')), findsNothing);
    });

    testWidgets('every row carries the canonical action menu', (tester) async {
      await _pumpDirectory(tester, _FakeApi(),
          session: _session(EntityType.INTESHAR, {Capability.MANAGE_AGENTS}));
      expect(find.byType(EntityRowActionsButton), findsNWidgets(3));
    });
  });
}

// ── Fake ApiClient ────────────────────────────────────────────────────────────

/// Serves the three entity reads the directory makes. Everything else throws:
/// the figure columns and the onboarding chips are each allowed to fail on their
/// own and simply not render, which is the behaviour under test everywhere else.
class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  int searchCalls = 0;
  int childrenCalls = 0;
  String? lastSearchType;
  String? lastSearchQuery;

  static final List<Map<String, dynamic>> _rows = [
    {
      'id': 'a1',
      'name': 'Baghdad Main',
      'type': 'AGENT1',
      'parentName': 'Inteshar',
      'childrenCount': 1,
      'productsCount': 120,
      'userCount': 2,
      'governorates': ['BG'],
    },
    {
      'id': 'a2',
      'name': 'Karkh Sub',
      'type': 'AGENT2',
      'parentName': 'Baghdad Main',
      'childrenCount': 1,
      'productsCount': 0,
      'userCount': 1,
      'governorates': ['BG'],
    },
    {
      'id': 's1',
      'name': 'Saad Shop',
      'type': 'STORE',
      'parentName': 'Karkh Sub',
      'childrenCount': 0,
      'productsCount': 0,
      'userCount': 1,
    },
  ];

  Response<dynamic> _ok(String path, dynamic data) => Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'status': 200, 'message': 'ok', 'data': data},
      );

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    if (path == Endpoints.entitySearch) {
      searchCalls++;
      lastSearchType = params?['type'] as String?;
      lastSearchQuery = params?['q'] as String?;
      final type = lastSearchType;
      final rows = type == null
          ? _rows
          : [for (final r in _rows) if (r['type'] == type) r];
      return _ok(path, {'items': rows, 'page': 0, 'size': 50, 'hasMore': false});
    }
    if (path == Endpoints.entityChildren) {
      childrenCalls++;
      final parent = params?['parentId'] as String?;
      // One level under the root; deeper nodes are only fetched on expand.
      final rows = parent == 'viewer' ? [_rows.first] : const <Map<String, dynamic>>[];
      return _ok(path, {'items': rows, 'page': 0, 'size': 50, 'hasMore': false});
    }
    if (path == Endpoints.entityRead) {
      return _ok(path, {
        'id': 'viewer',
        'meta': {'name': 'Inteshar'},
        'type': 'INTESHAR',
        'childrenIds': ['a1'],
        'productsIds': const <String>[],
        'users': const <Map<String, dynamic>>[],
      });
    }
    throw UnsupportedError('_FakeApi: unexpected GET $path');
  }
}

/// Pumps the directory inside a router, because its rows push routes.
Future<void> _pumpDirectory(
  WidgetTester tester,
  _FakeApi api, {
  required AuthAuthenticated session,
  EntityType? initialType,
}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Tear the previous tree down first. Pumping a second scenario straight over
  // the first reuses the ProviderScope element, so the overridden session is
  // swapped UNDER a page that has already built — and the viewer gates read the
  // auth provider rather than watching it, so they would keep answering for the
  // previous role. Two scenarios in one test then silently test one.
  await tester.pumpWidget(const SizedBox.shrink());

  final router = GoRouter(
    initialLocation: '/entities',
    routes: [
      GoRoute(
        path: '/entities',
        builder: (_, _) => Scaffold(
          body: EntityDirectoryPage(initialType: initialType),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authStateProvider.overrideWith(() => _StubAuth(session)),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
