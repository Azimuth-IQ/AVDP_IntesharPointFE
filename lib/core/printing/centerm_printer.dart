import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The built-in head on Centerm-based terminals (the ROVOO MTHD-M1 fleet),
/// driven with raw ESC/POS over the vendor AIDL.
///
/// This is the Rovo counterpart of [SunmiPrinter]: the same bytes, straight to
/// the head. It is what lets a Rovo receipt match a Sunmi one exactly, instead
/// of being re-rendered by the vendor's print app.
class CentermPrinter {
  static const _channel = MethodChannel('inteshar/centerm_printer');

  /// True only on a device carrying `com.centerm.printerservice`.
  static Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sends raw ESC/POS to the built-in head. Throws if the vendor service
  /// refuses — a silent success here would mean a sold voucher and no paper.
  static Future<void> printRaw(List<int> bytes) async {
    await _channel.invokeMethod('printRaw', {
      'bytes': Uint8List.fromList(bytes),
    });
  }
}
