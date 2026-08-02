import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/receipt_raster.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';

/// B-118: the printed PIN must stay on ONE line at any length.
///
/// A PIN broken across two lines is read back wrong — the customer keys in half
/// of it, or reads the wrap as a space or a dash. PIN length varies by operator
/// and denomination, so a fixed font size either wraps the long ones or wastes
/// paper on every short one.
///
/// These assert RELATIVE geometry (wrapped vs not, shrunk vs not) rather than
/// pixel counts: the test font is not the device font, so an absolute width
/// claim here would be fiction. The relation holds under any font because both
/// sides of each comparison render with the same one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 58mm paper, the width the voucher builder uses.
  const width = 384;

  const shortPin = '1234';
  const longPin = '0008178371555301234567890123';

  double heightOf(TextBlock b) {
    b.measure(width);
    return b.height;
  }

  TextBlock pinBlock(String pin, {bool singleLine = true}) => TextBlock(
        pin,
        fontSize: 46,
        letterSpacing: 2,
        singleLine: singleLine,
        minFontSize: 18,
      );

  group('the PIN never wraps', () {
    test('a long PIN would wrap without the fix — control', () {
      // Proves the hazard is real at this size, so the test below is meaningful
      // rather than asserting a property that held anyway.
      final wrapped = heightOf(pinBlock(longPin, singleLine: false));
      final oneLine = heightOf(pinBlock(shortPin, singleLine: false));
      expect(wrapped, greaterThan(oneLine),
          reason: 'the long PIN must genuinely overflow one line at 46px');
    });

    test('with the fix it occupies a single line', () {
      final long = pinBlock(longPin);
      final short = pinBlock(shortPin);
      final longH = heightOf(long);
      final shortH = heightOf(short);
      // One line of smaller type can only be shorter than one line of big type.
      expect(longH, lessThanOrEqualTo(shortH),
          reason: 'a wrapped PIN would be TALLER than the short one');
    });

    test('it shrinks only as far as needed, and never past the floor', () {
      final long = pinBlock(longPin)..measure(width);
      final short = pinBlock(shortPin)..measure(width);
      expect(short.renderedFontSize, 46,
          reason: 'a PIN that already fits must not be shrunk');
      expect(long.renderedFontSize, lessThan(46));
      expect(long.renderedFontSize, greaterThanOrEqualTo(18));
    });

    test('an absurdly long PIN still stays on one line', () {
      // One line is the invariant: past the floor it accepts smaller type
      // rather than wrapping.
      final absurd = pinBlock('9' * 120);
      final h = heightOf(absurd);
      final short = heightOf(pinBlock(shortPin));
      expect(h, lessThanOrEqualTo(short));
    });
  });

  group('the label/value pair carries it through', () {
    test('the value shrinks; a short one is untouched', () {
      final long = LabelValueBlock('PIN', longPin,
          valueSize: 46, valueSpacing: 2, singleLineValue: true, minValueSize: 18)
        ..measure(width);
      final short = LabelValueBlock('PIN', shortPin,
          valueSize: 46, valueSpacing: 2, singleLineValue: true, minValueSize: 18)
        ..measure(width);
      expect(short.renderedValueSize, 46);
      expect(long.renderedValueSize, lessThan(46));
      expect(long.height, lessThanOrEqualTo(short.height));
    });
  });

  test('a real receipt with a long PIN still builds', () async {
    final bytes = await buildVoucherReceipt(
      template: const VoucherTemplate(
        qrEnabled: false,
        showAgentLogo: false,
        showCompanyLogo: false,
      ),
      headerFallback: 'انتشار',
      shopName: 'محل سعد',
      productName: 'اسيا سيل 5000',
      price: '5000',
      serial: '10317061784',
      pin: longPin,
      timestamp: DateTime(2026, 8, 1, 12, 0),
      labelPin: 'الرقم السري',
    );
    expect(bytes, isNotEmpty);
  });
}
