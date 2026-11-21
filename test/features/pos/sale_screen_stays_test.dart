import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PROD-020 (client video, 2026-11-21 12:25): after a sale the card must stay on screen until
/// the cashier goes back, and the code may leave the shop only on paper — no Copy, no Share.
/// The sale sheet is a private widget fed by the API and the printer, so the rule is guarded
/// at the source.
void main() {
  final src = File('lib/features/pos/presentation/pos_home_page.dart').readAsStringSync();

  String body(String signature) {
    final start = src.indexOf(signature);
    expect(start, isNonNegative, reason: 'missing $signature');
    final next = src.indexOf('\n  Future<void> ', start + signature.length);
    return src.substring(start, next < 0 ? src.length : next);
  }

  test('a successful print does not close the sheet', () {
    final print = body('Future<void> _print() async {');
    expect(print, isNot(contains('widget.onPrinted()')));
    expect(print, contains('_printedOnce = true'));
  });

  test('the sheet is still closed by «تم»', () {
    expect(src, contains('label: l.posDone'));
    expect(src, contains('() => widget.onPrinted()'));
  });

  test('no Copy PIN and no Share on the sale sheet', () {
    expect(src, isNot(contains('Icons.copy')));
    expect(src, isNot(contains('SharePlus')));
    expect(src, isNot(contains("'نسخ الرمز'")));
    expect(src, isNot(contains('ClipboardData(text: pin)')));
  });
}
