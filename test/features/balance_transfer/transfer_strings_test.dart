import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/balance_transfer/presentation/transfers_page.dart';

/// B-113: the Send button read a literal "Confirm: send $amount to $to" on
/// screen — `\$` inside a Dart single-quoted string is an ESCAPED dollar, not
/// interpolation, so the placeholders were never substituted. Money buttons that
/// don't state the amount are the ones people click without reading.
void main() {
  test('the confirm label substitutes the real amount and recipient', () {
    for (final ar in [false, true]) {
      final s = transferStringsFor(ar);
      final out = s.confirmSend('25,876,000 IQD', 'مكتب سعد');
      expect(out.contains('25,876,000 IQD'), isTrue, reason: 'amount missing: $out');
      expect(out.contains('مكتب سعد'), isTrue, reason: 'recipient missing: $out');
      expect(out.contains(r'$amount'), isFalse, reason: 'raw placeholder leaked: $out');
      expect(out.contains(r'$to'), isFalse, reason: 'raw placeholder leaked: $out');
    }
  });

  test('take-back names its source, not a destination (UX-27)', () {
    // The reclaim picker was labelled "To" / "إلى" while the balance moves FROM
    // the account it names — a label pointing the opposite way to the money.
    final en = transferStringsFor(false);
    final ar = transferStringsFor(true);
    expect(en.from, 'From');
    expect(ar.from, 'من');
    expect(en.from, isNot(en.to));
    expect(ar.from, isNot(ar.to));
  });

  test('the two languages actually differ', () {
    final en = transferStringsFor(false).confirmSend('1', 'x');
    final ar = transferStringsFor(true).confirmSend('1', 'x');
    expect(ar, isNot(en));
    expect(RegExp(r'[؀-ۿ]').hasMatch(ar), isTrue);
  });
}
