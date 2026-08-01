import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';

/// Renders a voucher receipt to a 1-bit-friendly raster.
///
/// **Why a raster and not ESC/POS text.** `Generator.text()` encodes with
/// Latin-1, so a single Arabic character throws
/// `Invalid argument (string): Contains invalid characters` — the receipt could
/// not be BUILT, let alone printed, for any real Iraqi content. Code pages
/// (CP864 / Windows-1256) would not save it either: they need every printer model
/// in the fleet to support the page AND the app to do Arabic shaping itself.
///
/// Flutter's text engine already does the hard parts — contextual letter forms,
/// RTL ordering, bidi runs mixing Arabic with Latin digits — so the receipt is
/// laid out here and shipped as pixels. That also makes CR-06's promise literal:
/// every printer receives the same bitmap, so the paper cannot differ by device.
///
/// The QR is drawn into the same bitmap rather than sent as an ESC/POS command,
/// so its size and position are ours too.
Future<img.Image> renderReceiptRaster({
  required int width,
  required List<ReceiptBlock> blocks,
}) async {
  // Pass 1: measure. Every block knows its own height at this width.
  for (final b in blocks) {
    b.measure(width);
  }
  final totalHeight = blocks.fold<double>(0, (sum, b) => sum + b.height);

  // Pass 2: paint onto white.
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final h = totalHeight.ceil().clamp(1, 20000);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  var y = 0.0;
  for (final b in blocks) {
    b.paint(canvas, width, y);
    y += b.height;
  }

  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(width, h);
  final png = await uiImage.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  uiImage.dispose();
  if (png == null) {
    throw StateError('Could not rasterize the receipt');
  }
  final decoded = img.decodePng(png.buffer.asUint8List());
  if (decoded == null) {
    throw StateError('Could not decode the rasterized receipt');
  }
  // Grayscale keeps imageRaster's luminance threshold predictable.
  return img.grayscale(decoded);
}

/// One vertical element of the receipt.
abstract class ReceiptBlock {
  double _height = 0;
  double get height => _height;

  void measure(int width);
  void paint(ui.Canvas canvas, int width, double y);
}

/// True when [s] carries Arabic — used to pick the paragraph direction so a
/// mixed line ("PIN: ١٢٣" / "اسيا سيل 5000") orders correctly.
bool containsArabic(String s) =>
    RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]')
        .hasMatch(s);

class TextBlock extends ReceiptBlock {
  final String text;
  final double fontSize;
  final FontWeight weight;
  final TextAlign align;
  final double padTop;
  final double padBottom;
  final double letterSpacing;

  /// Never wrap: shrink the type until the text fits on ONE line.
  ///
  /// For the PIN this is correctness, not neatness. A code broken across two
  /// lines is read back wrong — the customer keys in half of it, or reads the
  /// wrap as a space or a dash. Denominations differ per operator, so the PIN
  /// length is not fixed and any single font size that fits the longest code
  /// would waste the paper for every shorter one.
  final bool singleLine;

  /// Floor for [singleLine] shrinking. Below this thermal output stops being
  /// legible, so the block stays on one line and accepts the smaller type
  /// rather than wrapping — one line is the invariant.
  final double minFontSize;

  TextPainter? _painter;

  TextBlock(
    this.text, {
    this.fontSize = 22,
    this.weight = FontWeight.normal,
    this.align = TextAlign.center,
    this.padTop = 0,
    this.padBottom = 3,
    this.letterSpacing = 0,
    this.singleLine = false,
    this.minFontSize = 14,
  });

  /// The size [text] was actually painted at — equals [fontSize] unless
  /// [singleLine] had to shrink it. Exposed so a test can prove the fit.
  double get renderedFontSize => _rendered;
  double _rendered = 0;

  @override
  void measure(int width) {
    final avail = width.toDouble() - 8;
    var size = fontSize;
    var spacing = letterSpacing;

    if (singleLine) {
      // Measure unconstrained, then scale once — a search loop would cost
      // several layout passes per block for the same answer.
      final probe = _paint(text, size, spacing, maxLines: 1)
        ..layout(maxWidth: double.infinity);
      final natural = probe.width;
      if (natural > avail && natural > 0) {
        final scale = avail / natural;
        size = (size * scale).clamp(minFontSize, fontSize);
        // Tracking has to shrink with the type or it eats the space just freed.
        spacing = spacing * scale;
      }
    }

    // Deliberately NOT pinned to the brand font: a receipt has to render Arabic
    // above all, so the platform font stack is allowed to supply glyphs the
    // bundled face lacks.
    final tp = _paint(text, size, spacing, maxLines: singleLine ? 1 : null)
      ..layout(maxWidth: avail);
    _painter = tp;
    _rendered = size;
    _height = tp.height + padTop + padBottom;
  }

  TextPainter _paint(String s, double size, double spacing, {int? maxLines}) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: const ui.Color(0xFF000000),
            fontSize: size,
            fontWeight: weight,
            letterSpacing: spacing,
            // Thermal paper is unforgiving: leading that is fine on a screen
            // reads as cramped once printed at 203 dpi.
            height: 1.35,
          ),
        ),
        textAlign: align,
        textDirection:
            containsArabic(s) ? TextDirection.rtl : TextDirection.ltr,
        maxLines: maxLines,
      );

  @override
  void paint(ui.Canvas canvas, int width, double y) {
    final tp = _painter;
    if (tp == null) return;
    // TextPainter aligns inside the width it was laid out with, so a single
    // offset places every alignment correctly.
    tp.paint(canvas, ui.Offset(4, y + padTop));
  }
}

class RuleBlock extends ReceiptBlock {
  final double padTop;
  final double padBottom;
  RuleBlock({this.padTop = 3, this.padBottom = 4});

  @override
  void measure(int width) => _height = 2 + padTop + padBottom;

  @override
  void paint(ui.Canvas canvas, int width, double y) {
    canvas.drawRect(
      ui.Rect.fromLTWH(8, y + padTop, width.toDouble() - 16, 2),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
  }
}

class GapBlock extends ReceiptBlock {
  final double size;
  GapBlock(this.size);

  @override
  void measure(int width) => _height = size;

  @override
  void paint(ui.Canvas canvas, int width, double y) {}
}

/// A pre-decoded logo, scaled to at most [maxWidth] dots and centred.
class ImageBlock extends ReceiptBlock {
  final img.Image image;
  final int maxWidth;
  final double padBottom;
  ui.Image? _ui;
  late double _drawW;
  late double _drawH;

  ImageBlock(this.image, {this.maxWidth = 200, this.padBottom = 4});

  /// Decoding to a `ui.Image` is async, so it happens before layout.
  Future<void> prepare() async {
    final png = img.encodePng(image);
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    _ui = frame.image;
  }

  @override
  void measure(int width) {
    final u = _ui;
    if (u == null) {
      _height = 0;
      return;
    }
    final cap = maxWidth.clamp(1, width).toDouble();
    final scale = u.width > cap ? cap / u.width : 1.0;
    _drawW = u.width * scale;
    _drawH = u.height * scale;
    _height = _drawH + padBottom;
  }

  @override
  void paint(ui.Canvas canvas, int width, double y) {
    final u = _ui;
    if (u == null) return;
    final dx = (width - _drawW) / 2;
    canvas.drawImageRect(
      u,
      ui.Rect.fromLTWH(0, 0, u.width.toDouble(), u.height.toDouble()),
      ui.Rect.fromLTWH(dx, y, _drawW, _drawH),
      ui.Paint(),
    );
  }
}

/// The redeem QR, drawn into the receipt bitmap so its size and placement are
/// ours rather than the printer's interpretation of `GS ( k`.
class QrBlock extends ReceiptBlock {
  final String data;
  final double size;
  final double padBottom;
  QrPainter? _painter;

  QrBlock(this.data, {this.size = 150, this.padBottom = 4});

  @override
  void measure(int width) {
    try {
      _painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: ui.Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: ui.Color(0xFF000000),
        ),
      );
      _height = size + padBottom;
    } catch (_) {
      // An unencodable payload must not cost the customer their receipt.
      _painter = null;
      _height = 0;
    }
  }

  @override
  void paint(ui.Canvas canvas, int width, double y) {
    final p = _painter;
    if (p == null) return;
    canvas.save();
    canvas.translate((width - size) / 2, y);
    try {
      p.paint(canvas, ui.Size(size, size));
    } catch (_) {
      // Ditto: skip the QR rather than fail the print.
    }
    canvas.restore();
  }
}

/// A label above its value, centred — the print counterpart of the on-screen
/// `_ReceiptRow`, so the paper carries the same wording and hierarchy as the
/// voucher the operator just looked at (`الرقم السري` / `الرقم التسلسلي`, not a
/// hardcoded English "PIN:").
class LabelValueBlock extends ReceiptBlock {
  final String label;
  final String value;
  final double labelSize;
  final double valueSize;
  final FontWeight valueWeight;
  final double valueSpacing;
  final double padBottom;

  late TextBlock _label;
  late TextBlock _value;

  /// Keep [value] on one line, shrinking it to fit (see [TextBlock.singleLine]).
  final bool singleLineValue;

  /// Floor for that shrinking.
  final double minValueSize;

  LabelValueBlock(
    this.label,
    this.value, {
    this.labelSize = 22,
    this.valueSize = 30,
    this.valueWeight = FontWeight.w700,
    this.valueSpacing = 0,
    this.padBottom = 8,
    this.singleLineValue = false,
    this.minValueSize = 14,
  });

  /// What the value was actually painted at, for tests.
  double get renderedValueSize => _value.renderedFontSize;

  @override
  void measure(int width) {
    _label = TextBlock(label, fontSize: labelSize, padBottom: 1);
    _value = TextBlock(
      value,
      fontSize: valueSize,
      weight: valueWeight,
      letterSpacing: valueSpacing,
      padBottom: 0,
      singleLine: singleLineValue,
      minFontSize: minValueSize,
    );
    _label.measure(width);
    _value.measure(width);
    _height = _label.height + _value.height + padBottom;
  }

  @override
  void paint(ui.Canvas canvas, int width, double y) {
    _label.paint(canvas, width, y);
    _value.paint(canvas, width, y + _label.height);
  }
}
