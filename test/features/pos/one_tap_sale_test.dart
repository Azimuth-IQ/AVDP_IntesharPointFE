import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/features/pos/presentation/pos_home_page.dart';

/// PROD-014: the client wants one tap on "Sell" to sell and print — no scrolling down to a Print
/// button — and no locked "مخفي حتى الإظهار" box before the sale.
void main() {
  group('a sale prints by itself when a printer is selected', () {
    test('connected → prints', () {
      expect(autoPrintAfterSale(const PrinterState(status: PrinterStatus.connected)), isTrue);
    });

    test('selected but the last probe failed → still prints (UX-55: a probe can be wrong)', () {
      expect(autoPrintAfterSale(const PrinterState(status: PrinterStatus.unreachable)), isTrue);
    });

    test('no printer, still connecting, a choice pending, or failed → shows the code instead', () {
      for (final s in [
        PrinterStatus.idle,
        PrinterStatus.connecting,
        PrinterStatus.needsChoice,
        PrinterStatus.error,
      ]) {
        expect(autoPrintAfterSale(PrinterState(status: s)), isFalse, reason: '$s');
      }
    });
  });

  // The sale sheet is a private widget fed by the API and the printer service; the wiring is
  // guarded at the source so a refactor cannot silently bring back the extra tap.
  group('the sale paths use it', () {
    final src = File('lib/features/pos/presentation/pos_home_page.dart').readAsStringSync();

    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, isNonNegative, reason: 'missing $signature');
      final next = src.indexOf('\n  Future<void> ', start + signature.length);
      return src.substring(start, next < 0 ? src.length : next);
    }

    test('one card: the draw is followed by _print()', () {
      expect(body('Future<void> _reveal() async {'),
          contains('if (autoPrintAfterSale(ref.read(printerServiceProvider))) unawaited(_print());'));
    });

    test('several cards: the draw is followed by _printAll()', () {
      expect(body('Future<void> _sellBulk() async {'),
          contains('if (autoPrintAfterSale(ref.read(printerServiceProvider))) unawaited(_printAll(res));'));
    });

    test('no locked box before the sale', () {
      final presale = src.substring(src.indexOf("'بيع وطباعة'") - 6000, src.indexOf("'بيع وطباعة'"));
      expect(presale, isNot(contains('_LockedQr(label: l.posPinHidden)')));
    });
  });

  test('the receipt preview draws the agent logo once (PROD-014 follow-up)', () {
    final src = File('lib/features/pos/presentation/pos_home_page.dart').readAsStringSync();
    final start = src.indexOf('Branding logos actually printed on the receipt');
    final block = src.substring(start, src.indexOf('t.headerText.trim().isNotEmpty', start));
    expect(block, contains("if (!(t.showAgentLogo && (_agentLogoUrl ?? '').trim().isNotEmpty)) ...["));
    expect(RegExp(r'^\s*const PosBrandMark\(size: 40\),', multiLine: true).allMatches(block), hasLength(1));
  });
}
