import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/printing/printer_target.dart';

/// A USB device currently attached over OTG.
class UsbPrinterDevice {
  /// `vendorId:productId` — stable across replugs of the same model.
  final String id;
  final String name;
  final int vendorId;
  final int productId;

  /// The device exposes a USB printer-class (0x07) interface. Anything else is
  /// almost certainly not a printer and must never be auto-selected.
  final bool isPrinterClass;

  /// Android grants USB access per device, per app, and it does not survive a
  /// replug unless the user ticked "always". Without it, writes fail.
  final bool hasPermission;

  const UsbPrinterDevice({
    required this.id,
    required this.name,
    required this.vendorId,
    required this.productId,
    this.isPrinterClass = false,
    this.hasPermission = false,
  });

  factory UsbPrinterDevice.fromMap(Map<dynamic, dynamic> m) => UsbPrinterDevice(
    id: (m['id'] as String?) ?? '',
    name: ((m['name'] as String?) ?? '').trim(),
    vendorId: (m['vendorId'] as int?) ?? 0,
    productId: (m['productId'] as int?) ?? 0,
    isPrinterClass: (m['isPrinterClass'] as bool?) ?? false,
    hasPermission: (m['hasPermission'] as bool?) ?? false,
  );

  PrinterTarget toTarget() => PrinterTarget(
    transport: PrinterTransport.usb,
    id: id,
    name: name.isNotEmpty ? name : id,
  );
}

/// USB (OTG) bulk-transfer printing — counter-attached printers.
///
/// Native side: `UsbPrinterChannel.kt` finds the printer-class interface, claims
/// it and pushes our ESC/POS bytes through its bulk-OUT endpoint. Same bytes as
/// every other transport.
class UsbPrinter {
  static const _channel = MethodChannel('inteshar/usb_printer');

  static bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<List<UsbPrinterDevice>> list() async {
    if (!_supportedPlatform) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('list');
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(UsbPrinterDevice.fromMap)
          .where((d) => d.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> hasPermission(String id) async {
    if (!_supportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission', {'id': id}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system USB-permission dialog and completes with the answer.
  /// Never called automatically at POS start — a dialog nobody asked for on the
  /// sale screen is its own kind of failure.
  static Future<bool> requestPermission(String id) async {
    if (!_supportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission', {
            'id': id,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> write(String id, List<int> bytes) async {
    if (!_supportedPlatform) {
      throw UnsupportedError('USB printing is Android-only');
    }
    await _channel.invokeMethod('write', {
      'id': id,
      'bytes': Uint8List.fromList(bytes),
    });
  }
}
