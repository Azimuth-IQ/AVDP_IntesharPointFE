// Tests for [SkuSummary.availableValue] — the inventory value card's per-SKU value.
//
// The backend prices each per-governorate [GovBucket].availableValue at the entity's
// EFFECTIVE price (per-gov override ?? SKU-wide base ?? defaultPrice). The card sums
// SkuSummary.availableValue across SKUs, so this getter MUST sum its buckets (not
// re-derive available * defaultPrice, which would ignore agent pricing). When there are
// no buckets (older backend / empty response) it falls back to available * defaultPrice
// so the card never drops to 0 mid-rollout.
//
// All tests are pure (no network, no widgets).

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';

void main() {
  group('SkuSummary.availableValue', () {
    test('sums the per-governorate buckets (effective-priced), not available * defaultPrice', () {
      // defaultPrice 5000, but the buckets carry effective values (base 5250, Baghdad 6000).
      const s = SkuSummary(
        sku: 'ASIA',
        defaultPrice: 5000,
        available: 5,
        governorates: [
          GovBucket(governorate: '', available: 3, availableValue: 3 * 5250), // base override
          GovBucket(governorate: 'BAGHDAD', available: 2, availableValue: 2 * 6000), // per-gov override
        ],
      );

      // Σ buckets = 15750 + 12000 = 27750  (NOT 5 * 5000 = 25000 at default price)
      expect(s.availableValue, 27750);
    });

    test('falls back to available * defaultPrice when there are no buckets', () {
      const s = SkuSummary(sku: 'ZAIN', defaultPrice: 10000, available: 4);
      expect(s.governorates, isEmpty);
      expect(s.availableValue, 40000);
    });

    test('fromJson parses per-bucket availableValue and the getter sums them', () {
      final s = SkuSummary.fromJson({
        'sku': 'ASIA',
        'name': 'Asiacell',
        'defaultPrice': 5000,
        'available': 5,
        'governorates': [
          {'governorate': '', 'available': 3, 'availableValue': 15750},
          {'governorate': 'BAGHDAD', 'available': 2, 'availableValue': 12000},
        ],
      });
      expect(s.governorates.length, 2);
      expect(s.availableValue, 27750);
    });
  });
}
