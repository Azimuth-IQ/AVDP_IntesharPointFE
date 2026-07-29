import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/printing/rovo_printer.dart';
import 'package:inteshar/core/printing/sunmi_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothPrinterService extends Notifier<BluetoothPrinterState> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  bool _sunmi = false;
  bool _rovo = false;

  @override
  BluetoothPrinterState build() {
    _detectBuiltIn();
    return const BluetoothPrinterState();
  }

  /// Devices with a built-in printer expose it through a native channel — no Bluetooth
  /// scan/pair needed, so auto-detect it and mark it connected. Sunmi's InnerPrinter takes
  /// ESC/POS via AIDL; a Rovo/BLD device prints via an ACTION_SEND intent to its print
  /// service. Sunmi wins if both somehow resolve.
  Future<void> _detectBuiltIn() async {
    try {
      if (await SunmiPrinter.isAvailable()) {
        _sunmi = true;
        state = state.copyWith(
          status: PrinterStatus.connected,
          deviceName: 'Sunmi Printer',
        );
        return;
      }
      if (await RovoPrinter.isAvailable()) {
        _rovo = true;
        state = state.copyWith(
          status: PrinterStatus.connected,
          deviceName: 'Rovo Printer',
        );
        return;
      }
    } catch (_) {}
  }

  Stream<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults;
  }

  void stopScan() => FlutterBluePlus.stopScan();

  /// Printers that will NEVER show up in a scan (CR-05).
  ///
  /// A terminal's built-in printer — the Rovo's internal link is the reported
  /// case — is already **bonded** to the device and does not advertise, so
  /// `startScan()` can never surface it. Android exposes those through
  /// `bondedDevices`; `systemDevices` adds anything already connected. Both are
  /// no-ops on iOS, where the section simply doesn't render.
  ///
  /// Returns real devices, not just printers: a paired headset or phone lands
  /// here too, which is why the picker lists them under their own heading rather
  /// than mixed into the scan results.
  Future<List<BluetoothDevice>> knownDevices() async {
    final seen = <String, BluetoothDevice>{};
    try {
      for (final d in await FlutterBluePlus.bondedDevices) {
        seen[d.remoteId.str] = d;
      }
    } catch (_) {/* unsupported platform / permission denied */}
    try {
      // 1800 = Generic Access; every GATT peripheral exposes it.
      for (final d in await FlutterBluePlus.systemDevices([Guid('1800')])) {
        seen.putIfAbsent(d.remoteId.str, () => d);
      }
    } catch (_) {}
    final out = seen.values.toList()
      ..sort((a, b) {
        // Anything that names itself a printer first — on a POS terminal that is
        // almost always the built-in head the operator is looking for.
        final ap = looksLikePrinterName(a.platformName) ? 0 : 1;
        final bp = looksLikePrinterName(b.platformName) ? 0 : 1;
        if (ap != bp) return ap - bp;
        return a.platformName.toLowerCase().compareTo(b.platformName.toLowerCase());
      });
    return out;
  }

  /// Name-only predicate — pure, so it is testable without a BluetoothDevice
  /// (which cannot be constructed with a name outside the plugin).
  static bool looksLikePrinterName(String name) {
    final n = name.toLowerCase();
    // Substring matches must be specific enough not to catch everyday devices:
    // a bare 'rp' matches "AiRPods", which a test caught. Model prefixes are
    // matched with their separator.
    return n.contains('print') ||
        n.contains('rovo') ||
        n.contains('bld') ||
        n.contains('inner') ||
        n.contains('escpos') ||
        n.contains('pos-') ||
        n.contains('pos_') ||
        n.startsWith('pos') ||
        n.contains('rp-') ||
        n.startsWith('rp') ||
        n.contains('tm-');
  }

  /// Whether [device] advertises a name that reads like a printer — used to mark
  /// the likely candidate in the picker so an operator isn't guessing.
  static bool looksLikePrinter(BluetoothDevice device) =>
      looksLikePrinterName(device.platformName);

  Future<void> connect(BluetoothDevice device) async {
    state = state.copyWith(
      status: PrinterStatus.connecting,
      deviceName: device.platformName,
    );
    try {
      // Ensure any in-progress scan is fully stopped before opening a GATT
      // connection.  On Android the BLE scanner and GATT stack share internal
      // resources; connecting while a scan is still tearing down causes the
      // infamous GATT error 133 (ANDROID_SPECIFIC_ERROR).
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      // mtu: null disables the automatic MTU negotiation that flutter_blue_plus
      // performs right after connect().  Many cheap ESC/POS printers have
      // minimal BLE stacks that crash when hit with an immediate MTU request,
      // causing a GATT 133 disconnect.  We use the safe default (23 bytes) and
      // rely on our own chunking in send() instead.
      await device.connect(timeout: const Duration(seconds: 10), mtu: null);
      _device = device;

      final services = await device.discoverServices();
      for (final s in services) {
        final svcUuid = s.serviceUuid.str.toLowerCase();
        debugPrint('[BT] service: $svcUuid');
        for (final c in s.characteristics) {
          debugPrint(
            '[BT]   char: ${c.characteristicUuid.str.toLowerCase()} write=${c.properties.write} writeNoResp=${c.properties.writeWithoutResponse}',
          );
        }
      }
      for (final s in services) {
        final svcUuid = s.serviceUuid.str.toLowerCase();
        // Skip standard BLE GATT services. flutter_blue_plus returns short UUIDs
        // (e.g. "1800") rather than the canonical full form, so we check both:
        //   - Short form: 1800 (Generic Access), 1801 (Generic Attribute)
        //   - Long form:  0000xxxx-0000-1000-8000-00805f9b34fb
        const skipServices = {'1800', '1801'};
        final isStandardShort = skipServices.contains(svcUuid);
        final isStandardLong =
            svcUuid.startsWith('0000') &&
            svcUuid.endsWith('-0000-1000-8000-00805f9b34fb');
        if (isStandardShort || isStandardLong) {
          debugPrint('[BT] skipping standard service: $svcUuid');
          continue;
        }
        for (final c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            _writeChar = c;
            debugPrint(
              '[BT] selected char: ${c.characteristicUuid.str.toLowerCase()} in service: $svcUuid',
            );
            break;
          }
        }
        if (_writeChar != null) break;
      }
      debugPrint('[BT] writeChar=${_writeChar?.characteristicUuid.str}');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_printer_id', device.remoteId.str);
      await prefs.setString('last_printer_name', device.platformName);

      state = state.copyWith(
        status: PrinterStatus.connected,
        deviceName: device.platformName,
      );
    } catch (e) {
      // A failed connect (GATT 133, timeout, no writable characteristic…) must NOT leave the
      // UI stuck on "connecting" — reset to error and let the caller surface the failure.
      _device = null;
      _writeChar = null;
      try {
        await device.disconnect();
      } catch (_) {}
      state = const BluetoothPrinterState(status: PrinterStatus.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
    state = state.copyWith(status: PrinterStatus.idle, deviceName: null);
  }

  Future<void> send(List<int> bytes) async {
    if (_sunmi) {
      await SunmiPrinter.printRaw(bytes);
      return;
    }
    if (_writeChar == null) throw Exception('No printer connected');
    // Without explicit MTU negotiation the BLE ATT default is 23 bytes,
    // leaving exactly 20 bytes of payload per write.  Staying at 20 is safe
    // for all ESC/POS printers regardless of whether they negotiate a larger MTU.
    const chunkSize = 20;
    final withoutResponse = _writeChar!.properties.writeWithoutResponse;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      await _writeChar!.write(
        bytes.sublist(i, end),
        withoutResponse: withoutResponse,
      );
      if (withoutResponse) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }
  }

  /// Connect directly to a device by MAC address without scanning.
  /// Useful for printers that are not advertising (e.g. virtual BT on POS
  /// machines like Topwise T1) or devices that are simply off-screen during
  /// a scan window.
  Future<void> connectByAddress(String macAddress) async {
    final device = BluetoothDevice.fromId(macAddress);
    await connect(device);
  }

  bool get isConnected =>
      _sunmi ||
      _rovo ||
      (_device != null && state.status == PrinterStatus.connected);

  /// True when the active printer is a Rovo/BLD built-in — it prints via an intent
  /// (text or image), NOT the ESC/POS byte path, so the POS must branch on this.
  bool get isRovo => _rovo;

  Future<String?> get lastPrinterId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_printer_id');
  }
}

enum PrinterStatus { idle, connecting, connected, error }

class BluetoothPrinterState {
  final PrinterStatus status;
  final String? deviceName;

  const BluetoothPrinterState({
    this.status = PrinterStatus.idle,
    this.deviceName,
  });

  BluetoothPrinterState copyWith({PrinterStatus? status, String? deviceName}) =>
      BluetoothPrinterState(
        status: status ?? this.status,
        deviceName: deviceName ?? this.deviceName,
      );
}

final bluetoothServiceProvider =
    NotifierProvider<BluetoothPrinterService, BluetoothPrinterState>(
      BluetoothPrinterService.new,
    );
