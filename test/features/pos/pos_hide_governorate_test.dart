import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/pos/presentation/pos_home_page.dart';

/// PROD-012: the client — «اخفاء اسماء المحافظات بالتطبيق» and «الغي شريط البحث ما احتاجة». The POS
/// showed "BAGHDAD" under the company and, when a company had cards for two regions, a "choose a
/// governorate" step. Now: one tile per card type, no governorate anywhere, no search bar.
void main() {
  SellableSku card(String sku, String? gov, {int available = 5, int affordable = 5, num price = 1000}) =>
      SellableSku(sku: sku, name: sku, companyName: 'ASIACELL', governorate: gov,
          available: available, affordable: affordable, price: price);

  group('posMergeRegions — one tile per card type', () {
    test('Baghdad and all-Iraq cards of the same type become one tile, Baghdad first', () {
      final out = posMergeRegions([card('AC-1000', null), card('AC-1000', 'BAGHDAD')]);
      expect(out, hasLength(1));
      expect(out.single.governorate, 'BAGHDAD');
    });

    test('when the shop\'s own region is sold out, the tile sells the all-Iraq cards', () {
      final out = posMergeRegions([
        card('AC-1000', 'BAGHDAD', available: 0, affordable: 0),
        card('AC-1000', null, available: 7, affordable: 7, price: 1100),
      ]);
      expect(out.single.governorate, isNull);
      expect(out.single.price, 1100, reason: 'the price shown is the one the sale will charge');
    });

    test('a bucket the shop can afford beats one it cannot', () {
      final out = posMergeRegions([
        card('AC-1000', 'BAGHDAD', available: 5, affordable: 0, price: 1300),
        card('AC-1000', null, available: 5, affordable: 2, price: 1200),
      ]);
      expect(out.single.governorate, isNull);
    });

    test('nothing sellable anywhere: one tile (it reads "unavailable"), the own region', () {
      final out = posMergeRegions([
        card('AC-1000', null, available: 0, affordable: 0),
        card('AC-1000', 'BAGHDAD', available: 0, affordable: 0),
      ]);
      expect(out, hasLength(1));
      expect(out.single.governorate, 'BAGHDAD');
    });

    test('different card types stay separate, in their original order', () {
      final out = posMergeRegions([
        card('AC-5000', 'BAGHDAD'),
        card('AC-1000', 'BAGHDAD'),
        card('AC-5000', null),
      ]);
      expect(out.map((s) => s.sku), ['AC-5000', 'AC-1000']);
    });
  });

  group('the POS screen', () {
    final src = File('lib/features/pos/presentation/pos_home_page.dart').readAsStringSync();

    test('has no search bar', () {
      expect(src, isNot(contains('posHomeSearchHint')));
    });

    test('has no governorate step and never prints a governorate', () {
      expect(src, isNot(contains('اختر المحافظة')));
      expect(src, isNot(contains('_governorateStep')));
      expect(src, isNot(contains('بدون تخصيص')));
      expect(RegExp(r'Text\([^)]*\.governorate').hasMatch(src), isFalse);
    });
  });
}
