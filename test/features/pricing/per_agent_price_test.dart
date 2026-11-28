import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pricing/domain/price_sheet.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';

/// PROD-038 (client, 28 Nov 2026): one price per agent per category, never per governorate; and
/// Asiacell / Zain may not be priced below the price from above.
void main() {
  group('an uploaded sheet lands as one price per category', () {
    test('the row without a governorate wins over the governorate rows', () {
      final one = onePricePerCategory([
        {'sku': 'ASIA5', 'governorate': 'BAGHDAD', 'price': 100},
        {'sku': 'ASIA5', 'governorate': '', 'price': 1300},
        {'sku': 'ASIA5', 'governorate': 'BASRA', 'price': 1400},
        {'sku': 'ZAIN5', 'governorate': '', 'price': 900},
      ]);
      expect(one.rows, [
        {'sku': 'ASIA5', 'governorate': '', 'price': 1300},
        {'sku': 'ZAIN5', 'governorate': '', 'price': 900},
      ]);
      expect(one.merged, 2);
    });

    test('with only governorate rows the first one is used, without its governorate', () {
      final one = onePricePerCategory([
        {'sku': 'ASIA5', 'governorate': 'BAGHDAD', 'price': 1250},
        {'sku': 'ASIA5', 'governorate': 'BASRA', 'price': 1400},
      ]);
      expect(one.rows.single, {'sku': 'ASIA5', 'governorate': '', 'price': 1250});
      expect(one.merged, 1);
    });
  });

  group('the Asiacell / Zain floor', () {
    const asia = CategoryPriceRow(sku: 'ASIA5', parentPrice: 1200, priceFloor: true);
    const korek = CategoryPriceRow(sku: 'KOREK5', parentPrice: 1000);

    test('only a floored category has a floor', () {
      expect(asia.floor, 1200);
      expect(korek.floor, isNull, reason: 'every other company is unbound');
    });

    test('counts only prices under a floored category\'s floor', () {
      expect(
        belowFloorCount([asia, korek], [
          {'sku': 'ASIA5', 'price': 1100}, // under
          {'sku': 'ASIA5', 'price': 1200}, // at the floor is fine
          {'sku': 'KOREK5', 'price': 1}, // unbound
        ]),
        1,
      );
    });

    test('the server\'s new fields are read; an older server means no floor', () {
      final r = CategoryPriceRow.fromJson({'sku': 'ASIA5', 'parentPrice': 1200, 'priceFloor': true});
      expect(r.floor, 1200);
      expect(CategoryPriceRow.fromJson({'sku': 'ASIA5'}).floor, isNull);
    });

    test('no category is regional any more', () {
      const regional = CategoryPriceRow(sku: 'ASIA5', governorates: [GovPriceRow(governorate: 'BAGHDAD')]);
      expect(isRegionalRow(regional), isFalse);
    });
  });
}
