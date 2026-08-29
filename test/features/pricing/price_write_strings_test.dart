// UX-88 — a bulk price write must say how many prices, not just that it worked.
//
// The spreadsheet path is the tool for "set 200 prices" and it confirmed with
// "Applied to 2 account(s)": the only number in the sentence counted the accounts,
// so the operator who had just uploaded a 200-row file learned nothing about the
// 200 rows — and nothing about a write that stopped short.
//
// These assert the real strings the page emits — `pricingStringsFor` is the
// page's own `_S`, not a copy of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pricing/presentation/pricing_page.dart';

void main() {
  final en = pricingStringsFor(false);
  final ar = pricingStringsFor(true);

  group('a bulk write names the prices AND the accounts', () {
    test('a full upload names both counts', () {
      expect(en.appliedPrices(200, 2), 'Applied 200 prices to 2 accounts');
      expect(ar.appliedPrices(200, 2), 'تم تطبيق 200 سعراً على حسابين');
    });

    test('a short write is reported as short, not as success', () {
      expect(en.appliedPricesPartial(190, 200, 2),
          'Applied 190 of 200 prices to 2 accounts');
      expect(ar.appliedPricesPartial(190, 200, 2),
          'تم تطبيق 190 من 200 سعر على حسابين');
    });

    test('the account count is present even for a single account', () {
      expect(en.appliedPrices(3, 1), 'Applied 3 prices to 1 account');
      expect(ar.appliedPrices(3, 1), 'تم تطبيق 3 أسعار على حساب واحد');
    });
  });

  group('the grid Save names its count', () {
    test('English reads as a sentence, not as "1 price(s)"', () {
      expect(en.savedN(1), '1 price saved');
      expect(en.savedN(7), '7 prices saved');
      expect(en.savedN(1).contains('(s)'), isFalse);
    });

    test('a short save still names both numbers', () {
      expect(en.savedPartial(4, 9).startsWith('Saved 4 of 9 prices'), isTrue);
      expect(ar.savedPartial(4, 9).startsWith('تم حفظ 4 من 9 سعر'), isTrue);
    });
  });

  group('Arabic number agreement', () {
    test('prices: singular, dual, broken plural, accusative singular', () {
      expect(ar.pricesPhrase(1), 'سعر واحد');
      expect(ar.pricesPhrase(2), 'سعرين');
      expect(ar.pricesPhrase(5), '5 أسعار');
      expect(ar.pricesPhrase(10), '10 أسعار');
      expect(ar.pricesPhrase(11), '11 سعراً');
      expect(ar.pricesPhrase(200), '200 سعراً');
    });

    test('accounts follow the same three-way agreement', () {
      expect(ar.accountsPhrase(1), 'حساب واحد');
      expect(ar.accountsPhrase(2), 'حسابين');
      expect(ar.accountsPhrase(4), '4 حسابات');
      expect(ar.accountsPhrase(18), '18 حساباً');
    });

    test('the parsed-rows readout uses the same agreement', () {
      expect(ar.parsed(2), 'تم قراءة سعرين');
      expect(ar.parsed(12), 'تم قراءة 12 سعراً');
      expect(en.parsed(12), '12 prices parsed');
    });

    test('the two languages actually differ and Arabic is Arabic', () {
      expect(ar.appliedPrices(5, 2), isNot(en.appliedPrices(5, 2)));
      expect(RegExp(r'[؀-ۿ]').hasMatch(ar.appliedPrices(5, 2)), isTrue);
      expect(ar.appliedPrices(5, 2).contains(r'$prices'), isFalse);
    });
  });
}
