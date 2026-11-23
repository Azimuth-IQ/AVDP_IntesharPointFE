import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pricing/presentation/pricing_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// PROD-026 (the owner, 23 Nov): a Main Agent opens the pricing page with their authenticator code,
/// every time, even though signed in. Nothing of the catalog is fetched before the code is accepted;
/// backing out leaves the page; leaving closes pricing on the server. HQ is not asked.
const _good = '123456';

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  /// Every call, in order: "GET /api/…" or "POST /api/…".
  final calls = <String>[];

  Response<dynamic> _ok(String path, dynamic data) => Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'status': 200, 'message': 'ok', 'data': data},
      );

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    calls.add('GET $path');
    if (path == Endpoints.pricingCatalog) {
      return _ok(path, {
        'rows': [
          {'sku': 'ZAIN-5000', 'name': 'زين 5,000', 'companyName': 'زين', 'officialPrice': 5000, 'effectivePrice': 5000},
        ],
      });
    }
    if (path == Endpoints.entityChildren) return _ok(path, {'items': [], 'hasMore': false});
    throw UnsupportedError('_FakeApi: unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data, Map<String, dynamic>? params}) async {
    calls.add('POST $path');
    if (path == Endpoints.pricingUnlock) {
      if ((data as Map)['totp'] != _good) throw const ApiException('That authentication code is not valid', 403);
      return _ok(path, {'required': true, 'minutes': 15});
    }
    if (path == Endpoints.pricingLock) return _ok(path, true);
    throw UnsupportedError('_FakeApi: unexpected POST $path');
  }
}

class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

AuthAuthenticated _session(EntityType type) => AuthAuthenticated(
      entity: Entity(id: 'me', meta: const EntityMeta(name: 'Me'), type: type),
      role: UserRole.ADMIN,
      effectiveCapabilities: {Capability.MANAGE_PRICING},
    );

/// Home at /agent1/home, the pricing page pushed on top — as an agent reaches it.
Future<(_FakeApi, GoRouter)> _open(WidgetTester tester, EntityType type) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _FakeApi();
  final router = GoRouter(initialLocation: '/agent1/home', routes: [
    GoRoute(path: '/agent1/home', builder: (_, _) => const Scaffold(body: Text('HOME'))),
    GoRoute(
      path: '/agent1/pricing',
      // The page reads the signed-in tier in initState: build it once the session is there.
      builder: (_, _) => Consumer(
        builder: (_, ref, _) =>
            // In the app the page sits inside the role shell's Scaffold.
            ref.watch(authStateProvider).hasValue ? const Scaffold(body: PricingPage()) : const SizedBox(),
      ),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith(() => _StubAuth(_session(type))),
    ],
    child: MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  router.push('/agent1/pricing');
  await tester.pumpAndSettle();
  return (api, router);
}

Future<void> _type(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextFormField), code);
  await tester.tap(find.widgetWithText(FilledButton, 'Open prices'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a main agent is asked for the code before any price is fetched; the right code opens it',
      (tester) async {
    final (api, _) = await _open(tester, EntityType.AGENT1);
    expect(find.text('Authentication code'), findsWidgets, reason: 'the prompt is up on entry');
    expect(api.calls, isNot(contains('GET ${Endpoints.pricingCatalog}')), reason: 'nothing fetched yet');

    await _type(tester, '000000');
    expect(find.text('That code is not right. Try the current code.'), findsOneWidget,
        reason: 'a wrong code asks again, saying why');
    expect(api.calls, isNot(contains('GET ${Endpoints.pricingCatalog}')));

    await _type(tester, _good);
    expect(find.byType(AlertDialog), findsNothing);
    final unlock = api.calls.lastIndexOf('POST ${Endpoints.pricingUnlock}');
    final catalog = api.calls.indexOf('GET ${Endpoints.pricingCatalog}');
    expect(catalog, greaterThan(unlock), reason: 'the catalog is fetched only after the unlock');
    expect(find.text('زين 5,000'), findsWidgets, reason: 'the prices are on screen');
  });

  testWidgets('backing out of the prompt leaves the page', (tester) async {
    final (api, _) = await _open(tester, EntityType.AGENT1);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(api.calls, isNot(contains('GET ${Endpoints.pricingCatalog}')));
  });

  testWidgets('leaving the page closes pricing on the server, so the next visit asks again',
      (tester) async {
    final (api, router) = await _open(tester, EntityType.AGENT1);
    await _type(tester, _good);
    router.pop();
    await tester.pumpAndSettle();
    expect(api.calls.last, 'POST ${Endpoints.pricingLock}');
    router.push('/agent1/pricing');
    await tester.pumpAndSettle();
    expect(find.text('Open prices'), findsOneWidget, reason: 'asked again on the next visit');
  });

  testWidgets('HQ is not asked', (tester) async {
    final (api, _) = await _open(tester, EntityType.INTESHAR);
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.calls, contains('GET ${Endpoints.pricingCatalog}'));
    expect(api.calls, isNot(contains('POST ${Endpoints.pricingUnlock}')));
  });
}
