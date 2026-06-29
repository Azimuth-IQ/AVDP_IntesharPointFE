// Tests for the catalog delete flow in DefinitionsPage.
//
// The backend refuses (409) to delete a category that still has vouchers. The
// page surfaces that message in a dialog and offers "Delete anyway" (a forced
// retry, force=true). These tests pin:
//   1. Cancel at the first confirm dialog → no DELETE call.
//   2. Confirm → 409 → the backend message + a "Delete anyway" action appear
//      (first delete carries no force flag).
//   3. "Delete anyway" → a second DELETE is issued WITH force=true.
//
// The fake ApiClient short-circuits all I/O — no network, no native channels.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/presentation/definitions_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

// ── Fake ApiClient ────────────────────────────────────────────────────────────

/// Intercepts GET/DELETE at the ApiClient level — the repository's real .unwrap
/// parses the {status,message,data} envelope.
class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  /// When true, an UNFORCED delete throws ApiException(409) (the backend refusing
  /// because vouchers still reference the SKU). A forced delete (force=true)
  /// always succeeds — mirroring the real endpoint.
  bool refuseUnlessForced = false;

  int deleteCallCount = 0;
  bool? lastForce; // the force flag seen on the most recent delete call

  static Map<String, dynamic> get _defJson => {
        'id': 'def-sc1',
        'name': 'SC1 Voucher',
        'sku': 'SC1',
        'defaultPrice': 5000,
        'description': 'Asiacell 5k IQD',
        'imageUrl': '',
      };

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    if (path == Endpoints.definitionReadAll) {
      return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'status': 200, 'message': 'ok', 'data': [_defJson]},
      );
    }
    throw UnsupportedError('_FakeApi: unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> delete(String path, {Map<String, dynamic>? params, dynamic data}) async {
    deleteCallCount++;
    final forced = params?['force'] == true;
    lastForce = forced;
    if (refuseUnlessForced && !forced) {
      throw ApiException('Cannot delete category SC1: 7 voucher(s) still exist', 409);
    }
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'status': 200, 'message': 'Deleted', 'data': null},
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> _pumpPage(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(500, 900);
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
        home: const DefinitionsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('SC1 Voucher'), findsOneWidget,
      reason: 'Page must display the canned definition before the test runs');
}

/// Fling the [Dismissible] for the SC1 row end→start to open the first confirm.
Future<void> _swipeToDelete(WidgetTester tester) async {
  await tester.fling(find.byKey(const ValueKey('def-sc1')), const Offset(-500, 0), 2000);
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('swipe + Cancel → confirm dialog appears but DELETE is never called',
      (tester) async {
    final api = _FakeApi();
    await _pumpPage(tester, api);
    await _swipeToDelete(tester);

    expect(find.text('Delete definition'), findsOneWidget);
    expect(find.text('Delete "SC1 Voucher"? This may break existing products.'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(api.deleteCallCount, 0, reason: 'DELETE must not be called on cancel');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('swipe + Confirm → 409 → backend message + "Delete anyway" action shown',
      (tester) async {
    final api = _FakeApi()..refuseUnlessForced = true;
    await _pumpPage(tester, api);
    await _swipeToDelete(tester);

    // First confirm dialog → tap Delete (unforced).
    expect(find.text('Delete definition'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // The backend refused: the 409 dialog shows the message + a force option.
    expect(api.deleteCallCount, 1, reason: 'first delete is attempted unforced');
    expect(api.lastForce, false, reason: 'the first delete carries no force flag');
    expect(find.textContaining('Cannot delete category SC1'), findsOneWidget,
        reason: 'the backend 409 message must be surfaced to the user');
    expect(find.widgetWithText(FilledButton, 'Delete anyway'), findsOneWidget,
        reason: 'a forced-delete option must be offered');
  });

  testWidgets('"Delete anyway" → a second DELETE is issued with force=true',
      (tester) async {
    final api = _FakeApi()..refuseUnlessForced = true;
    await _pumpPage(tester, api);
    await _swipeToDelete(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // Now confirm the forced delete.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete anyway'));
    await tester.pumpAndSettle();

    expect(api.deleteCallCount, 2, reason: 'the forced retry issues a second delete');
    expect(api.lastForce, true, reason: 'the retry must carry force=true');
    expect(find.byType(SnackBar), findsNothing,
        reason: 'a successful forced delete shows no error snackbar');
  });
}
