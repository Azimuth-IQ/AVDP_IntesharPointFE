import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over the native Sunmi InnerPrinter (`IWoyouService`) bound in
/// MainActivity. On Sunmi hardware the embedded thermal printer is driven via
/// this AIDL service — not Bluetooth — so ESC/POS bytes go straight to
/// `sendRAWData`.
class SunmiPrinter {
  static const _channel = MethodChannel('inteshar/sunmi_printer');

  /// True only on a Sunmi device whose InnerPrinter service is reachable.
  static Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sends raw ESC/POS bytes to the embedded printer (init → data → 3-line feed).
  static Future<void> printRaw(List<int> bytes) async {
    await _channel.invokeMethod('printRaw', {'bytes': Uint8List.fromList(bytes)});
  }
}
