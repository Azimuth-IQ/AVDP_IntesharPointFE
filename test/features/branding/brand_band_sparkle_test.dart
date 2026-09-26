import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/brand_band.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// The decorative star on a [BrandBand] is INTESHAR's own mark.
///
/// It used to be drawn for everyone, so a white-labelled agent got the Inteshar
/// star sitting behind their own logo, tinted with their own colour, and nothing
/// in the branding form would move it — the client reported exactly that on
/// 2026-09-26 ("اللوكو الخلفي مجاي يتغير"). The POS band had already been given
/// `sparkle: false` by hand; the rule now lives in the widget so it holds on the
/// bands nobody remembered to pass it to.
class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

Entity _entity(EntityType type) =>
    Entity(id: 'e', meta: const EntityMeta(name: 'Test'), type: type);

Future<void> _pump(WidgetTester tester, AuthState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith(() => _StubAuth(state))],
      child: const MaterialApp(
        home: BrandBand(child: Text('header')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('HQ keeps the Inteshar star', (tester) async {
    await _pump(
      tester,
      AuthAuthenticated(entity: _entity(EntityType.INTESHAR), role: UserRole.ADMIN),
    );
    expect(find.byType(IntesharStar), findsOneWidget);
  });

  testWidgets('a Main Agent does not get the Inteshar star', (tester) async {
    await _pump(
      tester,
      AuthAuthenticated(entity: _entity(EntityType.AGENT1), role: UserRole.ADMIN),
    );
    expect(find.byType(IntesharStar), findsNothing);
  });

  testWidgets('a shop under an agent does not get it either', (tester) async {
    // The mark is wrong on every white-labelled surface, not just the agent's own.
    await _pump(
      tester,
      AuthAuthenticated(entity: _entity(EntityType.STORE), role: UserRole.USER),
    );
    expect(find.byType(IntesharStar), findsNothing);
  });

  testWidgets('signed out, the band is the platform\'s own and keeps the star',
      (tester) async {
    // Splash and login are Inteshar's screens — nothing is white-labelled yet.
    await _pump(tester, AuthUnauthenticated());
    expect(find.byType(IntesharStar), findsOneWidget);
  });
}
