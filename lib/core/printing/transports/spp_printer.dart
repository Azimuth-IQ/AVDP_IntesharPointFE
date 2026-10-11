import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/printing/printer_target.dart';
import 'package:permission_handler/permission_handler.dart';

/// What stands between the app and the bonded-device list (B-150).
///
/// Android 12+ hides EVERY bonded device — the paired printer and a terminal's
/// built-in head alike (the Topwise T6 presents its head that way) — until the
/// app holds "Nearby devices" (`BLUETOOTH_CONNECT`). Without it the list is
/// simply empty, which used to read as "no printer here".
enum BluetoothAccess {
  /// The radio is on and the grant is held (always held below Android 12).
  ready,

  /// Not granted yet, and the system prompt can still be shown.
  askable,

  /// Denied for good: only the app's settings page can grant it now.
  blocked,

  /// Granted, but the radio is switched off.
  off,

  /// No Bluetooth to talk to: not Android, or no adapter.
  none,
}

/// A Bluetooth **Classic** device the OS has already bonded.
class SppDevice {
  final String address;
  final String name;

  /// The device declared itself an imaging/printer class over Bluetooth. Cheap
  /// units often declare nothing useful, so this is a hint, not a gate — the
  /// name heuristic covers the rest.
  final bool isPrinterClass;

  const SppDevice({
    required this.address,
    required this.name,
    this.isPrinterClass = false,
  });

  factory SppDevice.fromMap(Map<dynamic, dynamic> m) => SppDevice(
    address: (m['address'] as String?) ?? '',
    name: ((m['name'] as String?) ?? '').trim(),
    isPrinterClass: (m['isPrinterClass'] as bool?) ?? false,
  );

  /// Bonded devices carry a real name from `BluetoothDevice.getName()`; when the
  /// stack has none, the address at least tells two rows apart.
  PrinterTarget toTarget() => PrinterTarget(
    transport: PrinterTransport.spp,
    id: address,
    name: name.isNotEmpty ? name : address,
  );
}

/// Bluetooth Classic (RFCOMM / Serial Port Profile) — the transport almost every
/// external ESC/POS thermal printer actually uses.
///
/// `flutter_blue_plus` is BLE/GATT **only** (no `createRfcommSocket` anywhere in
/// its Android source), which is why connecting to an X-Printer or a terminal's
/// internal head never worked: wrong radio protocol, not a UI bug. This is a thin
/// wrapper over ~120 lines of native Kotlin (`SppPrinterChannel.kt`) that opens
/// the socket, writes our bytes and closes. Android-only; every call degrades to
/// a no-op/empty elsewhere.
class SppPrinter {
  static const _channel = MethodChannel('inteshar/spp_printer');

  static bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True when a Bluetooth adapter exists, is on, and we hold BLUETOOTH_CONNECT.
  static Future<bool> isSupported() async {
    if (!_supportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether [bondedDevices] can see anything, and if not, why (B-150).
  ///
  /// A lookup that fails (no plugin, an old embedding) answers [BluetoothAccess.ready]:
  /// "unknown" must never turn into a permission prompt.
  static Future<BluetoothAccess> access() async {
    if (!_supportedPlatform) return BluetoothAccess.none;
    try {
      final radio = await _channel.invokeMethod<String>('adapterState');
      if (radio == 'absent') return BluetoothAccess.none;
      final status = await Permission.bluetoothConnect.status;
      if (status.isPermanentlyDenied || status.isRestricted) return BluetoothAccess.blocked;
      if (!status.isGranted) return BluetoothAccess.askable;
      return radio == 'off' ? BluetoothAccess.off : BluetoothAccess.ready;
    } catch (_) {
      return BluetoothAccess.ready;
    }
  }

  /// Shows the system "Nearby devices" prompt. True when the grant is held after it.
  static Future<bool> requestAccess() async {
    if (!_supportedPlatform) return false;
    try {
      return (await Permission.bluetoothConnect.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's Bluetooth screen, for when the radio is off.
  static Future<void> openBluetoothSettings() async {
    if (!_supportedPlatform) return;
    try {
      await _channel.invokeMethod('openBluetoothSettings');
    } catch (_) {}
  }

  /// Every bonded Classic device — printers, but also headsets, phones and car
  /// kits. The caller must NOT treat this as a printer list.
  static Future<List<SppDevice>> bondedDevices() async {
    if (!_supportedPlatform) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('bondedDevices');
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(SppDevice.fromMap)
          .where((d) => d.address.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Opens (and caches) an RFCOMM socket. Throws on failure — an unreachable or
  /// powered-off printer must surface, not silently look connected.
  static Future<void> connect(String address) async {
    if (!_supportedPlatform) {
      throw UnsupportedError('Bluetooth Classic printing is Android-only');
    }
    await _channel.invokeMethod('connect', {'address': address});
  }

  /// Writes raw ESC/POS to [address], reconnecting first if the socket dropped.
  static Future<void> write(String address, List<int> bytes) async {
    if (!_supportedPlatform) {
      throw UnsupportedError('Bluetooth Classic printing is Android-only');
    }
    await _channel.invokeMethod('write', {
      'address': address,
      'bytes': Uint8List.fromList(bytes),
    });
  }

  static Future<void> disconnect() async {
    if (!_supportedPlatform) return;
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {}
  }
}
