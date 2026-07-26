import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/utils/formatters.dart';

/// B-093: money fields group as you type. The round-trip matters more than the
/// display — the field text now contains commas, so anything reading it back MUST
/// go through parseAmount or a transfer would be parsed as null/0.
void main() {
  const f = ThousandsInputFormatter();

  TextEditingValue apply(String text) =>
      f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

  group('grouping', () {
    test('groups in threes from the right', () {
      expect(apply('500000').text, '500,000');
      expect(apply('50000').text, '50,000');
      expect(apply('1234567').text, '1,234,567');
    });

    test('short values are untouched', () {
      expect(apply('5').text, '5');
      expect(apply('999').text, '999');
      expect(apply('1000').text, '1,000');
    });

    test('non-digits are stripped (also sanitises paste)', () {
      expect(apply('5o0,0 0d00').text, '500,000'); // 5-0-0-0-0-0
      expect(apply(r'IQD 25000').text, '25,000');
    });

    test('empty / no digits clears the field', () {
      expect(apply('').text, '');
      expect(apply('abc').text, '');
    });

    test('caret stays at the end so typing continues naturally', () {
      final v = apply('500000');
      expect(v.selection.baseOffset, v.text.length);
    });
  });

  group('parseAmount round-trip', () {
    test('reads a grouped field back to a plain number', () {
      expect(parseAmount(apply('500000').text), 500000);
      expect(parseAmount('1,234,567'), 1234567);
      expect(parseAmount('50,000'), 50000);
    });

    test('returns null when there is no digit — never 0 by accident', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('   '), isNull);
      expect(parseAmount(null), isNull);
      expect(parseAmount('abc'), isNull);
    });

    test('a raw num.parse on grouped text WOULD fail — hence parseAmount', () {
      const grouped = '500,000';
      expect(num.tryParse(grouped), isNull, reason: 'the bug parseAmount exists to prevent');
      expect(parseAmount(grouped), 500000);
    });
  });
}
