import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothPrinterService extends Notifier<BluetoothPrinterState> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;

  @override
  BluetoothPrinterState build() => const BluetoothPrinterState();

  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults;
  }

  void stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(BluetoothDevice device) async {
    state = state.copyWith(status: PrinterStatus.connecting, deviceName: device.platformName);
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
        debugPrint('[BT]   char: ${c.characteristicUuid.str.toLowerCase()} write=${c.properties.write} writeNoResp=${c.properties.writeWithoutResponse}');
      }
    }
    for (final s in services) {
      final svcUuid = s.serviceUuid.str.toLowerCase();
      // Skip standard BLE GATT services. flutter_blue_plus returns short UUIDs
      // (e.g. "1800") rather than the canonical full form, so we check both:
      //   - Short form: 1800 (Generic Access), 1801 (Generic Attribute)
      //   - Long form:  0000xxxx-0000-1000-8000-00805f9b34fb
      const _skipServices = {'1800', '1801'};
      final isStandardShort = _skipServices.contains(svcUuid);
      final isStandardLong = svcUuid.startsWith('0000') && svcUuid.endsWith('-0000-1000-8000-00805f9b34fb');
      if (isStandardShort || isStandardLong) {
        debugPrint('[BT] skipping standard service: $svcUuid');
        continue;
      }
      for (final c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          _writeChar = c;
          debugPrint('[BT] selected char: ${c.characteristicUuid.str.toLowerCase()} in service: $svcUuid');
          break;
        }
      }
      if (_writeChar != null) break;
    }
    debugPrint('[BT] writeChar=${_writeChar?.characteristicUuid.str}');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_printer_id', device.remoteId.str);
    await prefs.setString('last_printer_name', device.platformName);

    state = state.copyWith(status: PrinterStatus.connected, deviceName: device.platformName);
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
    state = state.copyWith(status: PrinterStatus.idle, deviceName: null);
  }

  Future<void> send(List<int> bytes) async {
    if (_writeChar == null) throw Exception('No printer connected');
    // Without explicit MTU negotiation the BLE ATT default is 23 bytes,
    // leaving exactly 20 bytes of payload per write.  Staying at 20 is safe
    // for all ESC/POS printers regardless of whether they negotiate a larger MTU.
    const chunkSize = 20;
    final withoutResponse = _writeChar!.properties.writeWithoutResponse;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      await _writeChar!.write(bytes.sublist(i, end), withoutResponse: withoutResponse);
      if (withoutResponse) await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  bool get isConnected => _device != null && state.status == PrinterStatus.connected;

  Future<String?> get lastPrinterId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_printer_id');
  }
}

enum PrinterStatus { idle, connecting, connected, error }

class BluetoothPrinterState {
  final PrinterStatus status;
  final String? deviceName;

  const BluetoothPrinterState({this.status = PrinterStatus.idle, this.deviceName});

  BluetoothPrinterState copyWith({PrinterStatus? status, String? deviceName}) => BluetoothPrinterState(status: status ?? this.status, deviceName: deviceName ?? this.deviceName);
}

final bluetoothServiceProvider = NotifierProvider<BluetoothPrinterService, BluetoothPrinterState>(BluetoothPrinterService.new);
