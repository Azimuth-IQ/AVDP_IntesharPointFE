import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/sku_from_name.dart';

/// The code a category gets when nobody types one. Asserts the produced string,
/// not the steps that produce it.
void main() {
  group('skuFromName', () {
    test('a plain latin name becomes an uppercase dashed code', () {
      expect(skuFromName('Asiacell weekly'), 'ASIACELL-WEEKLY');
    });

    test('thousands separators inside a number do not split it', () {
      expect(skuFromName('Asiacell 5,000'), 'ASIACELL-5000');
    });

    test('an arabic name keeps its own script', () {
      expect(skuFromName('آسياسيل 5,000'), 'آسياسيل-5000');
    });

    test('runs of punctuation and spaces collapse to one dash', () {
      expect(skuFromName('Zain  —  10 000'), 'ZAIN-10-000');
    });

    test('leading and trailing noise is dropped', () {
      expect(skuFromName('  ***Korek 1k!!!  '), 'KOREK-1K');
    });

    test('an empty or symbol-only name yields an empty code, not a dash', () {
      expect(skuFromName(''), '');
      expect(skuFromName('   '), '');
      expect(skuFromName('***'), '');
    });

    test('a long name is capped and never ends on a dash', () {
      final out = skuFromName('${'a' * 30} ${'b' * 30}');
      expect(out.length, lessThanOrEqualTo(40));
      expect(out.endsWith('-'), isFalse);
    });

    test('the result is safe to carry in a url or a spreadsheet cell', () {
      final out = skuFromName('Earthlink / monthly (unlimited) #1');
      expect(out, 'EARTHLINK-MONTHLY-UNLIMITED-1');
      expect(Uri.encodeQueryComponent(out), out,
          reason: 'a code needing escaping would break the sku query parameters');
    });

    test('digits alone survive', () {
      expect(skuFromName('1000'), '1000');
    });

    test('the derived code is stable for the same name', () {
      expect(skuFromName('Zain 25,000'), skuFromName('Zain 25,000'));
    });
  });
}
