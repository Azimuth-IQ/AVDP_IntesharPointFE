import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/voucher_batch.dart';

// ---------------------------------------------------------------------------
// Realistic JSON fixture: keys are those used in VoucherBatch.fromJson, which
// mirrors the backend batch-projection endpoint (GET /api/inventory/batches).
// Field names validated against:
//   avdp_inteshar_be/.../Inventory/Models/VoucherBatch.java  (id, sku, ownerId,
//   governorate, type, createdAt) and the enriched projection that adds
//   productName, ownerName, totalCount, availableCount, printedCount, status.
// ---------------------------------------------------------------------------

Map<String, dynamic> _fullJson({
  String id = 'batch-001',
  String sku = 'AC-5000',
  String productName = 'Asiacell 5000',
  String ownerId = 'inteshar-1',
  String? ownerName = 'Inteshar HQ',
  String type = 'NEW',
  String? governorate = 'Baghdad',
  int totalCount = 100,
  int availableCount = 80,
  int printedCount = 20,
  String status = 'ACTIVE',
  String createdAt = '2026-06-01T10:00:00Z',
}) =>
    {
      'id': id,
      'sku': sku,
      'productName': productName,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'type': type,
      'governorate': governorate,
      'totalCount': totalCount,
      'availableCount': availableCount,
      'printedCount': printedCount,
      'status': status,
      'createdAt': createdAt,
    };

void main() {
  // ── fromJson — full payload ───────────────────────────────────────────────

  group('VoucherBatch.fromJson — full payload', () {
    test('parses all string scalar fields', () {
      final b = VoucherBatch.fromJson(_fullJson());
      expect(b.id, 'batch-001');
      expect(b.sku, 'AC-5000');
      expect(b.productName, 'Asiacell 5000');
      expect(b.ownerId, 'inteshar-1');
      expect(b.ownerName, 'Inteshar HQ');
      expect(b.type, 'NEW');
      expect(b.governorate, 'Baghdad');
      expect(b.createdAt, '2026-06-01T10:00:00Z');
    });

    test('parses integer count fields', () {
      final b = VoucherBatch.fromJson(_fullJson(
        totalCount: 200,
        availableCount: 150,
        printedCount: 50,
      ));
      expect(b.totalCount, 200);
      expect(b.availableCount, 150);
      expect(b.printedCount, 50);
    });

    test('parses status ACTIVE', () {
      final b = VoucherBatch.fromJson(_fullJson(status: 'ACTIVE'));
      expect(b.status, BatchStatus.ACTIVE);
    });

    test('parses status PAUSED', () {
      final b = VoucherBatch.fromJson(_fullJson(status: 'PAUSED'));
      expect(b.status, BatchStatus.PAUSED);
    });

    test('parses type OTHER (region-free batch)', () {
      final b = VoucherBatch.fromJson(_fullJson(type: 'OTHER'));
      expect(b.type, 'OTHER');
    });
  });

  // ── fromJson — null / absent optional fields ──────────────────────────────

  group('VoucherBatch.fromJson — partial / missing fields', () {
    test('null ownerName stays null', () {
      final b = VoucherBatch.fromJson(_fullJson(ownerName: null));
      expect(b.ownerName, isNull);
    });

    test('absent ownerName key stays null', () {
      final json = Map<String, dynamic>.from(_fullJson())..remove('ownerName');
      final b = VoucherBatch.fromJson(json);
      expect(b.ownerName, isNull);
    });

    test('null governorate stays null (region-free)', () {
      final b = VoucherBatch.fromJson(_fullJson(governorate: null));
      expect(b.governorate, isNull);
    });

    test('absent governorate key stays null', () {
      final json = Map<String, dynamic>.from(_fullJson())..remove('governorate');
      final b = VoucherBatch.fromJson(json);
      expect(b.governorate, isNull);
    });

    test('absent productName defaults to empty string', () {
      final json = Map<String, dynamic>.from(_fullJson())..remove('productName');
      final b = VoucherBatch.fromJson(json);
      expect(b.productName, '');
    });

    test('absent type defaults to NEW', () {
      final json = Map<String, dynamic>.from(_fullJson())..remove('type');
      final b = VoucherBatch.fromJson(json);
      expect(b.type, 'NEW');
    });

    test('absent counts default to 0', () {
      final json = Map<String, dynamic>.from(_fullJson())
        ..remove('totalCount')
        ..remove('availableCount')
        ..remove('printedCount');
      final b = VoucherBatch.fromJson(json);
      expect(b.totalCount, 0);
      expect(b.availableCount, 0);
      expect(b.printedCount, 0);
    });

    test('absent status defaults to BatchStatus.ACTIVE', () {
      final json = Map<String, dynamic>.from(_fullJson())..remove('status');
      final b = VoucherBatch.fromJson(json);
      expect(b.status, BatchStatus.ACTIVE);
    });

    test('absent createdAt defaults to empty string', () {
      final json = Map<String, dynamic>.from(_fullJson())..remove('createdAt');
      final b = VoucherBatch.fromJson(json);
      expect(b.createdAt, '');
    });

    test('empty map produces safe defaults everywhere', () {
      final b = VoucherBatch.fromJson({});
      expect(b.id, '');
      expect(b.sku, '');
      expect(b.productName, '');
      expect(b.ownerId, '');
      expect(b.ownerName, isNull);
      expect(b.type, 'NEW');
      expect(b.governorate, isNull);
      expect(b.totalCount, 0);
      expect(b.availableCount, 0);
      expect(b.printedCount, 0);
      expect(b.status, BatchStatus.ACTIVE);
      expect(b.createdAt, '');
    });

    test('unknown status string falls back to ACTIVE', () {
      final b = VoucherBatch.fromJson(_fullJson(status: 'ARCHIVED'));
      expect(b.status, BatchStatus.ACTIVE);
    });

    test('numeric counts supplied as doubles are coerced to int', () {
      final json = Map<String, dynamic>.from(_fullJson())
        ..['totalCount'] = 10.0
        ..['availableCount'] = 8.0
        ..['printedCount'] = 2.0;
      final b = VoucherBatch.fromJson(json);
      expect(b.totalCount, 10);
      expect(b.availableCount, 8);
      expect(b.printedCount, 2);
    });
  });

  // ── derived getter: paused ────────────────────────────────────────────────

  group('VoucherBatch.paused getter', () {
    test('false when status is ACTIVE', () {
      final b = VoucherBatch.fromJson(_fullJson(status: 'ACTIVE'));
      expect(b.paused, isFalse);
    });

    test('true when status is PAUSED', () {
      final b = VoucherBatch.fromJson(_fullJson(status: 'PAUSED'));
      expect(b.paused, isTrue);
    });

    test('false when status falls back to ACTIVE (unknown string)', () {
      final b = VoucherBatch.fromJson(_fullJson(status: 'UNKNOWN'));
      expect(b.paused, isFalse);
    });
  });

  // ── derived getter: canDelete ─────────────────────────────────────────────

  group('VoucherBatch.canDelete getter', () {
    test('true when no vouchers have been printed/sold yet', () {
      final b = VoucherBatch.fromJson(_fullJson(printedCount: 0));
      expect(b.canDelete, isTrue);
    });

    test('false when at least one voucher has been printed', () {
      final b = VoucherBatch.fromJson(_fullJson(printedCount: 1));
      expect(b.canDelete, isFalse);
    });

    test('false when entire batch has been printed', () {
      final b = VoucherBatch.fromJson(
          _fullJson(totalCount: 50, availableCount: 0, printedCount: 50));
      expect(b.canDelete, isFalse);
    });

    test('empty map → printedCount 0 → canDelete true', () {
      final b = VoucherBatch.fromJson({});
      expect(b.canDelete, isTrue);
    });
  });

  // ── BatchStatus enum sanity ───────────────────────────────────────────────

  group('BatchStatus enum', () {
    test('has exactly ACTIVE and PAUSED values', () {
      expect(BatchStatus.values, containsAll([BatchStatus.ACTIVE, BatchStatus.PAUSED]));
      expect(BatchStatus.values.length, 2);
    });

    test('name strings match backend BatchStatus enum names', () {
      expect(BatchStatus.ACTIVE.name, 'ACTIVE');
      expect(BatchStatus.PAUSED.name, 'PAUSED');
    });
  });

  // ── const constructor / field integrity ──────────────────────────────────

  group('VoucherBatch const constructor', () {
    test('direct construction reflects all fields', () {
      const b = VoucherBatch(
        id: 'b-99',
        sku: 'ZN-10000',
        productName: 'Zain 10000',
        ownerId: 'agent-42',
        ownerName: 'Baghdad Agent',
        type: 'NEW',
        governorate: 'Anbar',
        totalCount: 300,
        availableCount: 250,
        printedCount: 50,
        status: BatchStatus.PAUSED,
        createdAt: '2026-05-15T08:30:00Z',
      );
      expect(b.id, 'b-99');
      expect(b.sku, 'ZN-10000');
      expect(b.productName, 'Zain 10000');
      expect(b.ownerId, 'agent-42');
      expect(b.ownerName, 'Baghdad Agent');
      expect(b.type, 'NEW');
      expect(b.governorate, 'Anbar');
      expect(b.totalCount, 300);
      expect(b.availableCount, 250);
      expect(b.printedCount, 50);
      expect(b.status, BatchStatus.PAUSED);
      expect(b.createdAt, '2026-05-15T08:30:00Z');
      expect(b.paused, isTrue);
      expect(b.canDelete, isFalse);
    });

    test('default type and status when not supplied', () {
      const b = VoucherBatch(
        id: 'b-min',
        sku: 'AC-1000',
        ownerId: 'inteshar-1',
        totalCount: 10,
        availableCount: 10,
        printedCount: 0,
      );
      expect(b.type, 'NEW');
      expect(b.status, BatchStatus.ACTIVE);
      expect(b.paused, isFalse);
      expect(b.canDelete, isTrue);
    });
  });
}
