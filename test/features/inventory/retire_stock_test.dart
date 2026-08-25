// C-19: the client half of retiring stock — parsing what the server sends back
// about cards taken out of circulation.
//
// All pure (no network, no widgets). The payloads below are the shapes the Java
// DTOs actually serialise (`StockRetireResult`, `RetiredLotRow`, `SkuSummary`),
// which is the thing worth pinning: a Dart default silently filling in for a
// field the server renamed is how a wrong number reaches a screen unnoticed.

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/inventory/domain/stock_retire_result.dart';

void main() {
  group('a retired voucher is not sellable stock', () {
    test('RETIRED survives the round trip instead of falling back to AVAILABLE', () {
      final p = Product.fromJson({
        'id': 'p1',
        'status': 'RETIRED',
        'serialNumber': 'SN-1',
        'pin': '',
        'currentOwner': 'hq-1',
        'productDefinition': {'sku': 'ASIA5'},
      });

      // fromJson falls back to AVAILABLE for a status it does not recognise, so a
      // value missing from the Dart enum would put a retired card back on the shelf.
      expect(p.status, ProductStatus.RETIRED);
      expect(p.status, isNot(ProductStatus.AVAILABLE));
    });

    test('an unknown status still falls back to AVAILABLE (the existing contract)', () {
      final p = Product.fromJson({
        'id': 'p1',
        'status': 'SOMETHING_NEW',
        'serialNumber': 'SN-1',
        'pin': '',
        'currentOwner': 'hq-1',
        'productDefinition': {'sku': 'ASIA5'},
      });
      expect(p.status, ProductStatus.AVAILABLE);
    });
  });

  group('the SKU card still adds up', () {
    // The header shows `total` beside a pill per status. A status the client does
    // not count lands in the total and in no pill, and the card stops adding up.
    test('retired is parsed and total equals the sum of the statuses', () {
      final s = SkuSummary.fromJson({
        'sku': 'ASIA5',
        'name': 'Asiacell 5k',
        'defaultPrice': 5000,
        'total': 10,
        'available': 4,
        'printed': 3,
        'damaged': 1,
        'sentForPrinting': 0,
        'failedPrinting': 0,
        'retired': 2,
        'governorates': [
          {
            'governorate': 'BAGHDAD',
            'total': 10,
            'available': 4,
            'printed': 3,
            'damaged': 1,
            'retired': 2,
            'availableValue': 20000,
          }
        ],
      });

      expect(s.retired, 2);
      expect(
        s.available + s.printed + s.damaged + s.sentForPrinting + s.failedPrinting + s.retired,
        s.total,
      );
      final b = s.governorates.single;
      expect(b.retired, 2);
      expect(
        b.available + b.printed + b.damaged + b.sentForPrinting + b.failedPrinting + b.retired,
        b.total,
      );
    });

    test('retired stock carries no sellable value', () {
      // Only AVAILABLE is priced by the server, so a bucket that is entirely
      // retired contributes nothing to the value card.
      final s = SkuSummary.fromJson({
        'sku': 'ASIA5',
        'defaultPrice': 5000,
        'total': 3,
        'available': 0,
        'retired': 3,
        'governorates': [
          {'governorate': '', 'total': 3, 'available': 0, 'retired': 3, 'availableValue': 0}
        ],
      });
      expect(s.availableValue, 0);
    });

    test('a server that does not send retired yet reads as zero, not as missing stock', () {
      final s = SkuSummary.fromJson({
        'sku': 'ASIA5',
        'total': 4,
        'available': 4,
      });
      expect(s.retired, 0);
    });
  });

  group('StockRetireResult', () {
    test('carries the undo handle and reports a short result', () {
      final r = StockRetireResult.fromJson({
        'fromEntityId': 'a1-1',
        'sku': 'ASIA5',
        'governorate': null,
        'requested': 100,
        'retired': 60,
        'remaining': 0,
        'retireRef': 'ref-1',
      });

      expect(r.retired, 60);
      expect(r.isShort, isTrue, reason: '"asked for 100, got 60" is the line worth showing');
      expect(r.retireRef, 'ref-1');
    });

    test('no undo is offered when nothing moved', () {
      final r = StockRetireResult.fromJson({
        'requested': 5,
        'retired': 0,
        'remaining': 0,
        'retireRef': null,
      });
      expect(r.retireRef, isNull);
      expect(r.isShort, isTrue);
    });

    test('a full result is not reported as short', () {
      final r = StockRetireResult.fromJson({
        'requested': 5,
        'retired': 5,
        'remaining': 0,
        'retireRef': 'ref-1',
      });
      expect(r.isShort, isFalse);
    });
  });

  group('RetiredLot', () {
    test('parses the lot the restore acts on', () {
      final lot = RetiredLot.fromJson({
        'retireRef': 'ref-1',
        'sku': 'ASIA5',
        'productName': 'Asiacell 5k',
        'governorate': 'BAGHDAD',
        'retiredFrom': 'a1-1',
        'retiredFromName': 'Baghdad Agent',
        'retiredBy': '07705371953',
        'count': 500,
        'retiredAt': '2026-08-25T10:00:00Z',
      });

      expect(lot.count, 500);
      expect(lot.displayFrom, 'Baghdad Agent');
      expect(lot.retiredAt, isNotNull);
    });

    test('an unnamed account still shows something', () {
      final lot = RetiredLot.fromJson({'retireRef': 'r', 'retiredFrom': 'a1-1'});
      expect(lot.displayFrom, 'a1-1');
      expect(lot.retiredAt, isNull);
    });
  });
}
