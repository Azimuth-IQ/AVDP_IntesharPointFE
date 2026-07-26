import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';

/// B-086: the POS stepper is driven entirely by the server's quote. These pin the
/// parsing and the "may I sell more than one?" gate — the client must never invent a
/// ceiling of its own (the server clamps again on draw, but the UI must not offer
/// a quantity that will be rejected).
void main() {
  group('BulkQuote parsing', () {
    test('reads the server clamp and the binding constraint', () {
      final q = BulkQuote.fromJson({
        'maxAllowed': 3,
        'configuredLimit': 10,
        'unitPrice': 5000,
        'total': 15000,
        'limitedBy': 'CAP',
        'capRemaining': 3,
        'available': 40,
      });
      expect(q.maxAllowed, 3);
      expect(q.configuredLimit, 10);
      expect(q.limitedBy, 'CAP');
      expect(q.capRemaining, 3);
      expect(q.bulkEnabled, isTrue);
    });

    test('a missing payload degrades to the single-card path, never to "unlimited"', () {
      final q = BulkQuote.fromJson(const {});
      expect(q.maxAllowed, 1);
      expect(q.configuredLimit, 1);
      expect(q.bulkEnabled, isFalse, reason: 'no quote must not unlock bulk selling');
      expect(q.capRemaining, -1);
    });

    test('a configured limit of 1 disables bulk', () {
      final q = BulkQuote.fromJson({'maxAllowed': 1, 'configuredLimit': 1});
      expect(q.bulkEnabled, isFalse);
    });

    test('stock/balance clamps are reported even when the limit is generous', () {
      final stock = BulkQuote.fromJson(
          {'maxAllowed': 2, 'configuredLimit': 10, 'limitedBy': 'STOCK', 'available': 2});
      expect(stock.maxAllowed, 2);
      expect(stock.limitedBy, 'STOCK');

      final money = BulkQuote.fromJson(
          {'maxAllowed': 4, 'configuredLimit': 10, 'limitedBy': 'BALANCE'});
      expect(money.maxAllowed, 4);
      expect(money.limitedBy, 'BALANCE');
    });
  });

  group('BulkDrawResult', () {
    test('a full batch is not partial', () {
      const r = BulkDrawResult(batchRef: 'b1', requested: 5, sold: 5, total: 25000);
      expect(r.isPartial, isFalse);
    });

    test('a drained pool reports the shortfall and charges only what sold', () {
      const r = BulkDrawResult(
        batchRef: 'b1',
        requested: 5,
        sold: 2,
        shortfallReason: 'STOCK',
        unitPrice: 5000,
        total: 10000,
      );
      expect(r.isPartial, isTrue);
      expect(r.shortfallReason, 'STOCK');
      expect(r.total, r.unitPrice * r.sold,
          reason: 'the charge must always equal cards actually sold');
    });
  });
}
