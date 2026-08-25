import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/stock_transfer_result.dart';

/// C-19's transfer destination reports three outcomes that look alike from the
/// numbers alone, and the operator needs to tell them apart: everything moved,
/// some moved, and nothing moved *because the destination cannot sell it*.
///
/// The third is the one worth a test. "Transferred 0 of 50" against an agent who
/// visibly holds 50 cards reads as a broken button, and the next thing that
/// happens is someone presses it four more times.
void main() {
  StockTransferResult decode(Map<String, dynamic> j) =>
      StockTransferResult.fromJson(j);

  group('telling the three outcomes apart', () {
    test('a clean transfer is neither short nor blocked', () {
      final r = decode({'requested': 50, 'moved': 50, 'remaining': 0, 'deliverable': 0});
      expect(r.isShort, isFalse);
      expect(r.blockedByRegion, isFalse);
    });

    test('a short transfer is short but not blocked', () {
      // The agent had 20 of the 50 asked for. Ordinary, and not a geo-lock.
      final r = decode({'requested': 50, 'moved': 20, 'remaining': 0, 'deliverable': 0});
      expect(r.isShort, isTrue);
      expect(r.blockedByRegion, isFalse);
    });

    test('nothing moved while stock remains that this destination cannot sell', () {
      final r = decode({'requested': 50, 'moved': 0, 'remaining': 50, 'deliverable': 0});
      expect(r.blockedByRegion, isTrue,
          reason: 'the shelf is full; the destination is simply wrong for it');
    });

    test('an empty shelf is NOT reported as a region problem', () {
      // Nothing moved and nothing left. Saying "cannot be sold in their regions"
      // here would send the operator hunting a geo-lock that does not exist.
      final r = decode({'requested': 50, 'moved': 0, 'remaining': 0, 'deliverable': 0});
      expect(r.blockedByRegion, isFalse);
    });

    test('stock that IS deliverable but simply lost the race is not blocked', () {
      // Cards remain and are deliverable — they just sold between looking and
      // pressing. That is a retry, not a wrong destination.
      final r = decode({'requested': 50, 'moved': 0, 'remaining': 10, 'deliverable': 10});
      expect(r.blockedByRegion, isFalse);
    });
  });

  group('decoding the server DTO', () {
    test('reads every field the Java DTO sends', () {
      final r = decode({
        'fromEntityId': 'a1',
        'toEntityId': 'a2',
        'sku': 'ASIA5',
        'governorate': 'BAGHDAD',
        'requested': 10,
        'moved': 7,
        'remaining': 3,
        'deliverable': 2,
      });
      expect(r.fromEntityId, 'a1');
      expect(r.toEntityId, 'a2');
      expect(r.sku, 'ASIA5');
      expect(r.governorate, 'BAGHDAD');
      expect(r.requested, 10);
      expect(r.moved, 7);
      expect(r.remaining, 3);
      expect(r.deliverable, 2);
    });

    test('survives an absent field rather than throwing mid-transfer', () {
      // The counts arrive from Mongo, which returns an int for a whole number;
      // a missing key must not take down the screen that reports what moved.
      final r = decode({'moved': 4});
      expect(r.moved, 4);
      expect(r.requested, 0);
      expect(r.governorate, isNull);
    });
  });
}
