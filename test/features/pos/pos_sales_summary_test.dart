// UX-50: the POS التقارير panel used to total a window by fetching up to 40
// sequential pages of the sales feed and adding them up on the handheld — 2,000
// rows of JSON for one number — and then labelled the figure "partial" when it
// ran out of pages.
//
// The server answers that question in one request now, over the SAME criteria
// the feed is filtered by. These tests pin the two things that can go wrong with
// that: the walk coming back (in any form), and the total describing a different
// window than the rows listed under it. Plus the failure case, because "0 cards"
// is how an operator reads "I sold nothing today".
//
// The fake ApiClient short-circuits all I/O. Nothing here touches the sale path.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos/presentation/pos_sales_panel.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

const _store = Entity(
  id: 'store-1',
  meta: EntityMeta(name: 'Saad Shop', governorates: ['BAGHDAD']),
  profile: EntityProfile(ownerName: 'Saad Ali'),
  parent: 'agent2-1',
  type: EntityType.STORE,
);

/// A FULL first page — the condition that used to trigger the 40-page walk.
List<Map<String, dynamic>> _fullPage() => [
      for (var i = 0; i < 50; i++)
        {
          'id': 'op-$i',
          'receiptNo': 500 - i,
          'storeId': 'store-1',
          'productId': 'p-$i',
          'serialNumber': '1031706178$i',
          'sku': 'ASC-5000',
          'productName': 'Asiacell 5000',
          'createdAt': '2026-08-16T10:00:00',
          'soldPrice': 5000,
          'printed': true,
        }
    ];

/// The server's SalesSummary for the WHOLE window — deliberately larger than the
/// 50 rows the first page holds, so a total derived from the visible rows would
/// be a different number.
Map<String, dynamic> _summary() => {
      'cards': 300,
      'total': 1000000.0,
      'unpriced': 4,
      'notPrinted': 2,
      'byCategory': [
        {'sku': 'ASC-5000', 'category': 'Asiacell 5000', 'cards': 250, 'total': 900000.0},
        {'sku': 'ZN-10000', 'category': 'Zain 10000', 'cards': 50, 'total': 100000.0},
      ],
    };

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  final List<Map<String, dynamic>> feedCalls = [];
  final List<Map<String, dynamic>> summaryCalls = [];

  /// When true the summary endpoint fails; the feed keeps working.
  bool failSummary = false;

  /// When set, the summary request blocks until it completes — a slow server.
  Completer<void>? holdSummary;

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    Response<dynamic> ok(dynamic data) => Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'status': 200, 'message': 'ok', 'data': data},
        );

    switch (path) {
      case Endpoints.entityChain:
        return ok(<dynamic>[]);
      case Endpoints.productPrintOperations:
        feedCalls.add(Map<String, dynamic>.from(params ?? const {}));
        final page = (params?['page'] as int?) ?? 0;
        // Only page 0 has rows; a walk would visibly stop here, but it must not
        // happen at all.
        return ok(page == 0 ? _fullPage() : <dynamic>[]);
      case Endpoints.productPrintOperationsSummary:
        summaryCalls.add(Map<String, dynamic>.from(params ?? const {}));
        if (holdSummary != null) await holdSummary!.future;
        if (failSummary) throw ApiException('Sales summary unavailable', 500);
        return ok(_summary());
    }
    throw UnsupportedError('_FakeApi: unexpected GET $path');
  }
}

Future<void> _pump(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authStateProvider.overrideWith(
          () => _StubAuth(AuthAuthenticated(entity: _store, role: UserRole.USER)),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PosSalesPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Formatters.languageCode = 'en');
  tearDown(() => Formatters.languageCode = 'ar');

  testWidgets('a full first page no longer triggers a page walk', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    expect(api.feedCalls.length, 1,
        reason: 'the window is listed one page at a time, on demand');
    expect(api.feedCalls.single['page'], 0);
    expect(api.summaryCalls.length, 1, reason: 'the totals are one request');
  });

  testWidgets('the total is the window\'s, not the visible page\'s', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    // 50 rows × 5,000 = 250,000 is on screen; the window holds 300 cards worth
    // 1,000,000. The card must show the window.
    expect(find.text(Formatters.iqd(1000000)), findsOneWidget);
    expect(find.text(Formatters.iqd(250000)), findsNothing);
    expect(find.text('300'), findsOneWidget);
    // And it no longer apologises for being partial.
    expect(find.textContaining('partial'), findsNothing);
  });

  testWidgets('the totals are asked for over exactly the window being listed',
      (tester) async {
    // A total for a different window than the rows under it is the whole bug
    // class this endpoint exists to close.
    final api = _FakeApi();
    await _pump(tester, api);

    expect(api.summaryCalls.single['from'], api.feedCalls.single['from']);
    expect(api.summaryCalls.single['to'], api.feedCalls.single['to']);

    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();

    expect(api.feedCalls.length, 2);
    expect(api.summaryCalls.length, 2);
    expect(api.summaryCalls.last['from'], api.feedCalls.last['from']);
    expect(api.summaryCalls.last['to'], api.feedCalls.last['to']);
    expect(api.summaryCalls.last['from'], isNot(api.summaryCalls.first['from']),
        reason: 'the window really changed');
  });

  testWidgets('while a new window is being totalled, the old total is not shown',
      (tester) async {
    // The dates on screen change the instant a preset is tapped. A total left
    // over from الشهر sitting under اليوم's dates is a wrong number presented
    // with full confidence, for as long as the request takes.
    final api = _FakeApi();
    await _pump(tester, api);
    expect(find.text(Formatters.iqd(1000000)), findsOneWidget);

    final gate = Completer<void>();
    api.holdSummary = gate;
    await tester.tap(find.text('Yesterday'));
    await tester.pump();
    await tester.pump();

    expect(find.text(Formatters.iqd(1000000)), findsNothing,
        reason: "the previous window's takings must not be attributed to this one");
    expect(find.text('300'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(Formatters.iqd(1000000)), findsOneWidget);
  });

  testWidgets('a POS session never sends storeId — it is scoped server-side',
      (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    expect(api.summaryCalls.single.containsKey('storeId'), isFalse);
    expect(api.feedCalls.single.containsKey('storeId'), isFalse);
  });

  testWidgets('the per-category breakdown comes from the server, in its order',
      (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    expect(find.text('Asiacell 5000'), findsWidgets);
    expect(find.text('Zain 10000'), findsOneWidget,
        reason: 'a category with no row on the visible page is still in the total');
    expect(find.text('×250'), findsOneWidget);
    expect(find.text('×50'), findsOneWidget);
  });

  testWidgets('a failed summary says so — it never reads as "no sales"',
      (tester) async {
    final api = _FakeApi()..failSummary = true;
    await _pump(tester, api);

    expect(find.textContaining('could not be loaded'), findsOneWidget);
    // The zeros that would otherwise be shown must NOT be.
    expect(find.text('Cards'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text(Formatters.iqd(0)), findsNothing);
    // The rows themselves loaded fine and are still readable.
    expect(find.textContaining('SN 10317061780'), findsOneWidget);
    // Nothing may be put on paper from a total that does not exist.
    final print = tester.widget<FilledButton>(find.ancestor(
      of: find.text('Print report'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ));
    expect(print.onPressed, isNull);
  });

  testWidgets('the failed summary is retryable on its own', (tester) async {
    final api = _FakeApi()..failSummary = true;
    await _pump(tester, api);
    expect(api.feedCalls.length, 1);

    api.failSummary = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(api.summaryCalls.length, 2);
    expect(api.feedCalls.length, 1, reason: 'the list did not need reloading');
    expect(find.text(Formatters.iqd(1000000)), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets('a search asks for no window total at all', (tester) async {
    // A result set spanning every date is not a report of a window; totalling it
    // would answer a question nobody asked.
    final api = _FakeApi();
    await _pump(tester, api);
    expect(api.summaryCalls.length, 1);

    await tester.enterText(find.byType(TextField), '412');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(api.summaryCalls.length, 1, reason: 'no summary request for a search');
    expect(find.text(Formatters.iqd(1000000)), findsNothing,
        reason: 'the window total must not sit above search results');
  });
}
