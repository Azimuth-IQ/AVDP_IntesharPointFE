// UX-51: the POS الحسابات statement used to download its whole date window in
// one call and build a card for every row — thousands of them for a month at a
// busy shop, on an Android 7.1 handheld.
//
// It is paged now, and the thing paging can break on a STATEMENT is the running
// balance: a page of rows carries no memory of what came before it, so a client
// that recomputed the total from the rows it happens to hold would restart the
// account at zero halfway down the list. The server therefore brackets each page
// with the balance it opens and closes on. These tests read the rendered rows
// back and assert that the balance chain is continuous ACROSS the page boundary,
// which is the only property that actually matters here.
//
// The fake ApiClient short-circuits all I/O, and refuses the old unpaged route
// outright — calling it would fail the test rather than silently work.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/pos/presentation/pos_statement_panel.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

// ── The ledger under test ─────────────────────────────────────────────────────
//
// A shop that opens the window on 100,000, is granted 50,000, then sells three
// cards. Oldest → newest, with the running balance the server computes:
//
//   GRANT +50,000 → 150,000
//   SALE   −5,000 → 145,000
//   SALE   −5,000 → 140,000
//   SALE  −10,000 → 130,000
//
// Paged newest-first at size 2, that splits BETWEEN the two 5,000 sales — so the
// boundary is exactly where a client-side running total would go wrong.

Map<String, dynamic> _row(
  String type,
  String label,
  double? amount,
  double balanceAfter, {
  int? receiptNo,
}) =>
    {
      'at': '2026-08-16T10:00:00Z',
      'type': type,
      'label': label,
      'amount': amount,
      'balanceAfter': balanceAfter,
      // The server sends these as null on a GRANT row rather than omitting them.
      'receiptNo': receiptNo,
      'printed': receiptNo == null ? null : true,
    };

/// Page 0 — the two newest events.
Map<String, dynamic> get _page0 => {
      'items': [
        _row('SALE', 'Zain 10000', -10000, 130000, receiptNo: 4),
        _row('SALE', 'Asiacell 5000', -5000, 140000, receiptNo: 3),
      ],
      'page': 0,
      'size': 2,
      'hasMore': true,
      'openingBalance': 145000.0,
      'closingBalance': 130000.0,
      'windowOpeningBalance': 100000.0,
    };

/// Page 1 — the two oldest, opening on the window's own figure.
Map<String, dynamic> get _page1 => {
      'items': [
        _row('SALE', 'Asiacell 5000', -5000, 145000, receiptNo: 2),
        _row('GRANT', 'وكيل الرصافة', 50000, 150000),
      ],
      'page': 1,
      'size': 2,
      'hasMore': false,
      'openingBalance': 100000.0,
      'closingBalance': 145000.0,
      'windowOpeningBalance': 100000.0,
    };

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  /// Every page request the panel made, in order: `{page, size, from, to}`.
  final List<Map<String, dynamic>> calls = [];

  /// Pages keyed by index; a missing index is an empty tail.
  Map<int, Map<String, dynamic>> pages = {0: _page0, 1: _page1};

  /// When set, the request for this page index throws instead of answering.
  int? failPage;

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    if (path == Endpoints.posStatement) {
      // The unpaged route still exists server-side for already-shipped APKs.
      // This app must never call it again.
      throw StateError('the panel called the UNPAGED statement route');
    }
    if (path != Endpoints.posStatementPage) {
      throw UnsupportedError('_FakeApi: unexpected GET $path');
    }
    calls.add(Map<String, dynamic>.from(params ?? const {}));
    final page = (params?['page'] as int?) ?? 0;
    if (failPage == page) {
      throw ApiException('Network unreachable', null);
    }
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {
        'status': 200,
        'message': 'Statement',
        'data': pages[page] ??
            {
              'items': <dynamic>[],
              'page': page,
              'size': 2,
              'hasMore': false,
              'openingBalance': 100000.0,
              'closingBalance': 130000.0,
              'windowOpeningBalance': 100000.0,
            },
      },
    );
  }
}

Future<void> _pump(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PosStatementPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The "before → after" pair a row renders, as the operator reads it.
String _chain(int before, int after) =>
    '${Formatters.iqd(before)} → ${Formatters.iqd(after)}';

void main() {
  setUp(() => Formatters.languageCode = 'en');
  tearDown(() => Formatters.languageCode = 'ar');

  testWidgets('opens on ONE page, not the whole window', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    expect(api.calls.length, 1, reason: 'one page fetched on open');
    expect(api.calls.single['page'], 0);
    expect(api.calls.single['size'], isA<int>());
    // The oldest events are behind "Load more" — they must not already be built.
    expect(find.textContaining('Balance from'), findsNothing);
    expect(find.text('Load more'), findsOneWidget);
  });

  testWidgets('the running balance is continuous across the page boundary',
      (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    // Page 0's oldest row opens on 145,000 — a figure that lives on the page
    // BEFORE any of its own rows could establish it.
    expect(find.text(_chain(145000, 140000)), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    // The newest row of page 1 closes on exactly that 145,000: the account
    // continues, it does not restart.
    expect(find.text(_chain(150000, 145000)), findsOneWidget);
    // …and page 1 did NOT re-run the balance from zero, which is what a
    // client-side running total over "the rows I hold" would have produced.
    expect(find.text(_chain(0, -5000)), findsNothing);
    expect(find.text(_chain(50000, 0)), findsNothing);
    // The whole ledger is now on screen, oldest row included.
    expect(find.textContaining('Balance from وكيل الرصافة'), findsOneWidget);
  });

  testWidgets('the window opening balance comes from the envelope, not from page 0',
      (tester) async {
    // 100,000 is the balance before the window's FIRST event — which sits on the
    // last page. No arithmetic over page 0 alone can produce it, so a header
    // showing it proves the envelope figure is being used.
    final api = _FakeApi();
    await _pump(tester, api);

    expect(find.text('Opening balance'), findsOneWidget);
    expect(find.text(Formatters.iqd(100000)), findsOneWidget);
    expect(find.text('Closing balance'), findsOneWidget);
    expect(find.text(Formatters.iqd(130000)), findsOneWidget);
  });

  testWidgets('"Load more" follows the server\'s hasMore, not a full page',
      (tester) async {
    // Page 1 comes back FULL (2 of 2) with hasMore=false. Inferring "a full page
    // means more" would leave a Load more button that fetches nothing.
    final api = _FakeApi();
    await _pump(tester, api);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(find.text('Load more'), findsNothing);
    expect(api.calls.length, 2, reason: 'exactly two page fetches, no tail probe');
  });

  testWidgets('changing the window restarts at page 0 and replaces the rows',
      (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Balance from'), findsOneWidget);

    // A different window served by a different (single-page) ledger.
    api.pages = {
      0: {
        'items': [_row('SALE', 'Korek 1000', -1000, 99000, receiptNo: 9)],
        'page': 0,
        'size': 2,
        'hasMore': false,
        'openingBalance': 100000.0,
        'closingBalance': 99000.0,
        'windowOpeningBalance': 100000.0,
      }
    };
    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();

    expect(api.calls.last['page'], 0,
        reason: 'a new window must not keep the old page cursor');
    expect(find.text(_chain(100000, 99000)), findsOneWidget);
    // Nothing from the previous window may survive the switch.
    expect(find.textContaining('Balance from'), findsNothing);
    expect(find.text(_chain(150000, 145000)), findsNothing);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('a failed first page is an error, never "no activity"',
      (tester) async {
    final api = _FakeApi()..failPage = 0;
    await _pump(tester, api);

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('No activity in this window.'), findsNothing,
        reason: 'an operator reads that as "nothing happened today"');
  });

  testWidgets('a failed LATER page keeps the rows already read', (tester) async {
    final api = _FakeApi()..failPage = 1;
    await _pump(tester, api);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text(_chain(145000, 140000)), findsOneWidget,
        reason: 'page 0 was valid and is still valid');
    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'the failure has to be said out loud');
    expect(find.text('Load more'), findsOneWidget, reason: 'the tail is retryable');
  });
}
