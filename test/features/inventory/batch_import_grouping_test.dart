import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One batch per FILE (2026-09-29).
///
/// The upload goes up in 1,000-row requests. The server used to open a batch per
/// request, so a 6,500-row delivery became seven batches and every per-batch
/// operation had to be done seven times. Now chunk 1 opens the batch and the
/// server returns its id; every later chunk must carry that id back. These tests
/// drive the real repository through a fake transport and assert on the bodies
/// that actually leave the client.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statuses);
  final List<int> statuses;
  final List<Map<String, dynamic>> bodies = [];
  int _n = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final body = Map<String, dynamic>.from(options.data as Map);
    bodies.add(body);
    final status = statuses[_n++];
    final json = status < 300
        ? {
            'status': status,
            'message': 'Batch imported',
            'data': {
              'imported': (body['vouchers'] as List).length,
              'skipped': 0,
              'invalid': 0,
              'batchId': 'b-1',
              'assignedTo': 'a1',
            },
          }
        : {'status': status, 'message': 'boom', 'data': null};
    return ResponseBody.fromString(jsonEncode(json), status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

ProductRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;
  return ProductRepository(ApiClient(dio));
}

List<ParsedVoucher> _rows(int n) => [
      for (var i = 1; i <= n; i++) ParsedVoucher(serial: 'S-$i', pin: '0000$i'),
    ];

void main() {
  setUpAll(() {
    // ApiClient.post resolves the base URL from SessionStorage (SharedPreferences);
    // the fake adapter ignores the host, so an empty store is all it needs.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('chunk 1 opens the batch; every later chunk carries its id back', () async {
    final adapter = _FakeAdapter([201, 201, 201]);
    final res = await _repo(adapter).batchImport(
        definitionId: 'def-1', ownerId: 'a1', governorate: 'KARBALA', type: 'OTHER',
        vouchers: _rows(2500));

    expect(adapter.bodies, hasLength(3), reason: '2,500 rows in 1,000-row chunks');
    expect(adapter.bodies[0].containsKey('batchId'), isFalse,
        reason: 'the first request opens the batch — it has no id to send yet');
    expect(adapter.bodies[1]['batchId'], 'b-1');
    expect(adapter.bodies[2]['batchId'], 'b-1');
    expect(res.imported, 2500);
    expect(res.batchIds, ['b-1'], reason: 'one file, one batch — the id is not repeated per chunk');
  });

  test('a chunk that fails mid-file hands the retry the open batch id', () async {
    final adapter = _FakeAdapter([201, 500]);
    Object? thrown;
    try {
      await _repo(adapter).batchImport(
          definitionId: 'def-1', ownerId: 'a1', type: 'OTHER', vouchers: _rows(2500));
    } catch (e) {
      thrown = e;
    }
    final partial = thrown as PartialImportException;
    expect(partial.sentRows, 1000, reason: 'UX-85: rows before this ARE on the server');
    expect(partial.partial.imported, 1000);
    expect(partial.batchId, 'b-1', reason: 'the tail must be appended, not put in a new batch');
  });

  test('a retry resumes into the batch it was given, from the first request', () async {
    final adapter = _FakeAdapter([201, 201]);
    await _repo(adapter).batchImport(
        definitionId: 'def-1', ownerId: 'a1', type: 'OTHER',
        vouchers: _rows(2500), from: 1000, batchId: 'b-1');

    expect(adapter.bodies, hasLength(2), reason: 'rows 1000..2499 only');
    expect(adapter.bodies.every((b) => b['batchId'] == 'b-1'), isTrue);
    expect((adapter.bodies[0]['vouchers'] as List).first['serialNumber'], 'S-1001');
  });

  test('merge keeps a repeated batch id once but distinct ids in order', () {
    const a = BatchImportResult(imported: 1, batchIds: ['b-1']);
    const b = BatchImportResult(imported: 1, batchIds: ['b-1']);
    const c = BatchImportResult(imported: 1, batchIds: ['b-2']);
    expect(a.merge(b).batchIds, ['b-1']);
    expect(a.merge(b).merge(c).batchIds, ['b-1', 'b-2']);
    expect(a.merge(b).merge(c).imported, 3);
  });
}
