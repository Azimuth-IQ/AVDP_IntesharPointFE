import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Rovo / BLD-based POS devices print via an Android `ACTION_SEND` intent to their built-in
/// print service (`com.bld.settings.print`) — NOT Bluetooth and NOT ESC/POS. The intent
/// carries either plain text (in `EXTRA_TEXT`) or an absolute file path for an image/pdf,
/// with the matching MIME type. The native side lives in MainActivity. Because the service
/// ships on the device, it's always "connected" — no scan/pair, so the POS auto-detects it.
class RovoPrinter {
  static const _channel = MethodChannel('inteshar/rovo_printer');

  /// True only on a device that has the built-in print service installed.
  static Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Print plain text (EXTRA_TEXT, text/plain).
  static Future<void> printText(String text) async {
    await _channel.invokeMethod('printText', {'text': text});
  }

  /// Print an image by absolute file path — the service rasterizes + prints it (image/*).
  static Future<void> printImage(String path) async {
    await _channel.invokeMethod('printImage', {'path': path});
  }
}
