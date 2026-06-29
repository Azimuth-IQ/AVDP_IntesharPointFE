// Tests for the transaction stock pre-flight gate (lib/features/transactions/
// domain/tx_preflight.dart) — the SAME functions the new-transaction page's
// `_overAllocatedSkus`/submit gate delegate to, so these guard production, not a
// mirror copy.
//
// BRD rule (CLAUDE.md quirk #6): the backend TransactionProcessor does NOT
// filter by ProductStatus, so the client must verify the source holds >= amount
// AVAILABLE per SKU before submitting; otherwise a transfer can drain
// non-AVAILABLE (used/damaged) vouchers.
//
// All tests are pure (no network, no widgets, no timers).

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/transactions/domain/tx_preflight.dart';

void main() {
  group('overAllocatedSkus', () {
    test('empty when every SKU is within available stock', () {
      expect(overAllocatedSkus({'ASIA': 3, 'ZAIN': 2}, {'ASIA': 5, 'ZAIN': 2}), isEmpty);
    });

    test('exact-match (requested == available) is NOT over-allocated', () {
      expect(overAllocatedSkus({'ASIA': 5}, {'ASIA': 5}), isEmpty);
    });

    test('flags a SKU requested beyond its available count', () {
      expect(overAllocatedSkus({'ASIA': 6}, {'ASIA': 5}), ['ASIA']);
    });

    test('a SKU absent from availability (0 available) is over-allocated', () {
      expect(overAllocatedSkus({'ZAIN': 1}, {'ASIA': 10}), ['ZAIN']);
    });

    test('reports every over-allocated SKU across a multi-line manifest', () {
      final out = overAllocatedSkus(
        {'ASIA': 6, 'ZAIN': 1, 'KOREK': 4},
        {'ASIA': 5, 'ZAIN': 10, 'KOREK': 0},
      );
      expect(out.toSet(), {'ASIA', 'KOREK'});
    });

    test('zero requested is never over-allocated', () {
      expect(overAllocatedSkus({'ASIA': 0}, {'ASIA': 0}), isEmpty);
    });
  });

  group('shortfallBySku', () {
    test('empty when nothing is over-allocated', () {
      expect(shortfallBySku({'ASIA': 3}, {'ASIA': 5}), isEmpty);
    });

    test('reports requested - available per over-allocated SKU', () {
      expect(
        shortfallBySku({'ASIA': 8, 'ZAIN': 2}, {'ASIA': 5, 'ZAIN': 2}),
        {'ASIA': 3},
      );
    });

    test('a fully-unavailable SKU shortfalls by its full request', () {
      expect(shortfallBySku({'KOREK': 4}, {}), {'KOREK': 4});
    });

    test('multiple shortfalls reported together', () {
      expect(
        shortfallBySku({'ASIA': 7, 'ZAIN': 5}, {'ASIA': 5, 'ZAIN': 1}),
        {'ASIA': 2, 'ZAIN': 4},
      );
    });
  });

  group('preflightPasses (submit gate)', () {
    test('passes when all SKUs are fulfillable', () {
      expect(preflightPasses({'ASIA': 5, 'ZAIN': 2}, {'ASIA': 5, 'ZAIN': 3}), isTrue);
    });

    test('blocks when any single SKU is over-allocated', () {
      expect(preflightPasses({'ASIA': 5, 'ZAIN': 3}, {'ASIA': 5, 'ZAIN': 2}), isFalse);
    });

    test('passes on an empty manifest (nothing requested)', () {
      expect(preflightPasses({}, {'ASIA': 5}), isTrue);
    });

    test('blocks when the source holds none of the requested SKU', () {
      expect(preflightPasses({'ASIA': 1}, {}), isFalse);
    });

    test('is consistent with overAllocatedSkus/shortfallBySku', () {
      const requested = {'ASIA': 6, 'ZAIN': 2};
      const available = {'ASIA': 5, 'ZAIN': 2};
      final blocked = !preflightPasses(requested, available);
      expect(blocked, overAllocatedSkus(requested, available).isNotEmpty);
      expect(blocked, shortfallBySku(requested, available).isNotEmpty);
    });
  });
}
