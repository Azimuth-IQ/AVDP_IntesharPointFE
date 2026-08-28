import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_scaffold.dart';

/// UX-116 — the tablet navigation rail, guarded because it has been fixed twice.
///
/// The first fix bounded the rail with `IntrinsicHeight` + `ConstrainedBox`
/// inside a scroll view. `RenderConstrainedBox` does not clamp the width it is
/// asked about when computing intrinsic height, so the rail was measured as if
/// every label were one line, tightened to that height, and then laid out at the
/// real cap where the labels wrapped — overflowing the height it had been forced
/// into. The labels were not ellipsized; the bottom of the rail was cut off.
///
/// A render overflow throws in a widget test, so pumping the rail across the
/// whole tablet band IS the assertion. These cover both ends of that band and
/// the tier with the most destinations, which is the one that overflows first.
class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

Future<void> _pumpAt(WidgetTester tester, double width, EntityType type) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AuthAuthenticated(
    entity: Entity(
      id: 'e',
      // A long Arabic name: the rail sits beside the brand block, and Arabic
      // needs more height than Latin for the same legibility.
      meta: const EntityMeta(name: 'وكيل بغداد الرئيسي للاتصالات'),
      type: type,
    ),
    role: UserRole.ADMIN,
  );

  // A stub router with an EMPTY body, matching `mobile_nav_test`. The real
  // router lands on a data-loading screen whose spinner never settles, and this
  // is a test of the shell's layout, not of any page inside it.
  final router = GoRouter(
    initialLocation: '/hq/home',
    routes: [
      GoRoute(
        path: '/hq/:section',
        builder: (_, _) => const AppShell(child: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/agent1/:section',
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
  // 600 and 1199 are the declared edges of the tablet band; 601/1198 catch an
  // off-by-one in the breakpoint itself.
  for (final width in <double>[600, 601, 800, 1024, 1198, 1199]) {
    testWidgets('HQ rail lays out cleanly at ${width}dp', (tester) async {
      await _pumpAt(tester, width, EntityType.INTESHAR);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a Main Agent rail also lays out — its destination set differs',
      (tester) async {
    await _pumpAt(tester, 700, EntityType.AGENT1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rail is present in the tablet band', (tester) async {
    // Without this the checks below would pass trivially on any change that
    // removed the rail altogether.
    await _pumpAt(tester, 800, EntityType.INTESHAR);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('the rail scrolls itself — this is THE fix', (tester) async {
    // The bug was a hand-rolled `SingleChildScrollView` + `IntrinsicHeight` +
    // `ConstrainedBox` around the rail. `RenderConstrainedBox` forwards the
    // width unclamped when asked for an intrinsic height, so the rail was
    // measured as if every label were one line, tightened to that height, then
    // laid out at the real cap where labels wrapped — and the bottom was cut
    // off. `scrollable: true` is what removes the intrinsic pass entirely.
    //
    // Asserted directly because a "no overflow" assertion CANNOT catch this: a
    // scrollable rail scrolls instead of overflowing, so the exception never
    // fires. (Verified — forcing the rail to 44dp still threw nothing.)
    await _pumpAt(tester, 800, EntityType.INTESHAR);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.scrollable, isTrue,
        reason: 'without this the rail needs an intrinsic height pass, which is '
            'what cut the labels off twice');
  });

  testWidgets('the rail is width-bounded by a real SizedBox', (tester) async {
    // The other half of the fix: something concrete must state the width, so
    // nothing downstream has to infer it from an unbounded constraint.
    await _pumpAt(tester, 800, EntityType.INTESHAR);
    final box = tester.widget<SizedBox>(
      find.ancestor(of: find.byType(NavigationRail), matching: find.byType(SizedBox)).first,
    );
    expect(box.width, isNotNull);
    expect(box.width, greaterThanOrEqualTo(112),
        reason: 'below ~112dp the labels wrap and the rail stops being readable');
  });

  testWidgets('labels are rendered, not dropped for icons', (tester) async {
    // If a future fix "solves" clipping by hiding the labels, that is a
    // regression wearing a fix's clothes.
    await _pumpAt(tester, 800, EntityType.INTESHAR);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.labelType, NavigationRailLabelType.all);
  });

  testWidgets('the rail widens with the viewport instead of staying flat',
      (tester) async {
    // At the top of the tablet band a flat 116dp rail starved the labels while
    // ~1080dp of body sat unused.
    await _pumpAt(tester, 640, EntityType.INTESHAR);
    final narrow = tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .minWidth;
    await _pumpAt(tester, 1180, EntityType.INTESHAR);
    final wide =
        tester.widget<NavigationRail>(find.byType(NavigationRail)).minWidth;
    expect(wide, greaterThan(narrow!));
  });
}
