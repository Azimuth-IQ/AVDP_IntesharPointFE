import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/receipt_raster.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';

/// PROD-027: the paper must lay a line out like the preview — a centred header is centred, an
/// Arabic detail line sits on the right. PROD-030: the PIN prints inside a frame.
///
/// Geometry is read off the rendered raster (dark pixels), relative to the paper, so it holds
/// whatever font the test machine supplies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const width = 384;

  /// Leftmost and rightmost dark columns of [im] between rows [y0] and [y1].
  (int, int) inkSpan(img.Image im, {int y0 = 0, int? y1}) {
    var left = im.width, right = -1;
    for (var y = y0; y < (y1 ?? im.height); y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        if (p.r < 128) {
          if (x < left) left = x;
          if (x > right) right = x;
        }
      }
    }
    return (left, right);
  }

  group('PROD-027: lines are aligned on the paper as in the preview', () {
    test('a centred header is centred, not at the left edge', () async {
      final im = await renderReceiptRaster(width: width, blocks: [TextBlock('inteshar', fontSize: 36)]);
      final (l, r) = inkSpan(im);
      expect(r, greaterThan(l), reason: 'the text was drawn');
      final leftGap = l, rightGap = width - 1 - r;
      expect((leftGap - rightGap).abs(), lessThan(24),
          reason: 'left gap $leftGap vs right gap $rightGap — the client saw it printed at the left edge');
      // Before the fix the text started at x = 4 (the paint offset), whatever its alignment.
      expect(leftGap, greaterThan(20), reason: 'a short word must not sit at the edge');
    });

    test('an Arabic detail line starts on the right', () async {
      final im = await renderReceiptRaster(width: width, blocks: [
        FieldLineBlock('الرقم التسلسلي', '123', fontSize: 26, align: TextAlign.start),
      ]);
      final (l, r) = inkSpan(im);
      expect(width - 1 - r, lessThan(l), reason: 'start = right under RTL: the gap is on the left');
    });
  });

  group('PROD-030: the PIN is framed', () {
    test('a framed value is drawn inside a rectangle that spans the paper', () async {
      final framed = LabelValueBlock('الرقم السري', '000817889272898',
          valueSize: 46, singleLineValue: true, minValueSize: 18, valueMono: true, framed: true);
      final plain = LabelValueBlock('الرقم السري', '000817889272898',
          valueSize: 46, singleLineValue: true, minValueSize: 18, valueMono: true);
      final im = await renderReceiptRaster(width: width, blocks: [framed]);
      plain.measure(width);
      expect(framed.height, greaterThan(plain.height), reason: 'the frame adds room around the PIN');

      // Below the label, the frame's sides are dark columns near both edges of the paper.
      final labelBottom = (framed.height - (framed.height - plain.height)).floor() ~/ 3;
      final (l, r) = inkSpan(im, y0: labelBottom);
      expect(l, lessThanOrEqualTo(8));
      expect(r, greaterThanOrEqualTo(width - 9));
    });

    test('a long PIN still fits inside the frame on one line', () {
      final b = LabelValueBlock('PIN', '0008178371555301234567890123',
          valueSize: 46, singleLineValue: true, minValueSize: 18, valueMono: true, framed: true)
        ..measure(width);
      expect(b.renderedValueSize, lessThan(46), reason: 'it shrank to fit the narrower inside');
      expect(b.renderedValueSize, greaterThanOrEqualTo(18));
    });

    test('the receipt builder frames the PIN, and the text-only twin sets it apart', () async {
      final job = await buildVoucherPrintJob(
        template: const VoucherTemplate(),
        headerFallback: 'Shop',
        shopName: 'Shop',
        productName: 'Asiacell 5000',
        price: '5,000',
        serial: '10317062028',
        pin: '000817889272898',
        timestamp: DateTime(2026, 11, 25, 14, 24),
      );
      expect(job.text, contains('================================\nPIN: 000817889272898\n================================'));
    });
  });
}
