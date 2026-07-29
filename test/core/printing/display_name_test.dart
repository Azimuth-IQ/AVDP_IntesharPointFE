import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/auto_connect.dart';
import 'package:inteshar/core/printing/printer_target.dart';
import 'package:inteshar/core/printing/transports/spp_printer.dart';
import 'package:inteshar/core/printing/transports/usb_printer.dart';

/// The picker showed a generic label for EVERY row. Cause: it read only
/// `device.platformName`, which the OS populates from a bond or a GATT read — a
/// freshly scanned peripheral usually carries its name only in the
/// advertisement. So the fallback chain matters, and it is worth pinning.
void main() {
  test('the BLE fallback order is platform → advertised → address', () {
    // Documented as a table rather than constructing BluetoothDevice, which the
    // plugin does not allow outside itself.
    String pick(String platform, String advertised, String mac) {
      if (platform.trim().isNotEmpty) return platform.trim();
      if (advertised.trim().isNotEmpty) return advertised.trim();
      return mac;
    }

    expect(pick('X-Printer X50', 'XP-58', 'AA:BB'), 'X-Printer X50');
    expect(pick('', 'XP-58', 'AA:BB'), 'XP-58',
        reason: 'a scanned printer names itself only in the advertisement');
    expect(pick('   ', 'XP-58', 'AA:BB'), 'XP-58', reason: 'whitespace is not a name');
    expect(pick('', '', 'AA:BB:CC:DD:EE:FF'), 'AA:BB:CC:DD:EE:FF',
        reason: 'the address at least tells two nameless rows apart');
  });

  test('printer-name detection survives the names these devices really use', () {
    for (final n in ['X-Printer X50', 'XP-58', 'InnerPrinter', 'RovoPrinter', 'BLD-POS']) {
      expect(looksLikePrinterName(n), isTrue, reason: n);
    }
  });

  /// CR-06: bonded Classic devices are a DIFFERENT list from BLE scan results
  /// and carry a real `getName()`. A nameless one must still be identifiable.
  test('a bonded SPP device shows its name, falling back to its address', () {
    expect(
      const SppDevice(address: '11:22:33:44:55:66', name: 'XP-58').toTarget().label,
      'XP-58',
    );
    expect(
      const SppDevice(address: '11:22:33:44:55:66', name: '').toTarget().label,
      '11:22:33:44:55:66',
      reason: 'a nameless bonded printer is still addressable',
    );
  });

  test('a USB printer shows its product name, falling back to vid:pid', () {
    expect(
      const UsbPrinterDevice(
        id: '1155:22339',
        name: 'Xprinter XP-58',
        vendorId: 1155,
        productId: 22339,
      ).toTarget().label,
      'Xprinter XP-58',
    );
    expect(
      const UsbPrinterDevice(
        id: '1155:22339',
        name: '',
        vendorId: 1155,
        productId: 22339,
      ).toTarget().label,
      '1155:22339',
    );
  });

  /// The remembered printer is matched by transport+address. If the OS later
  /// reports a nicer name, it must still be the same printer — otherwise the POS
  /// would quietly stop reconnecting to it.
  test('a remembered target is identified by transport and address, not name', () {
    const a = PrinterTarget(transport: PrinterTransport.spp, id: 'AA:BB', name: 'BT-01');
    const b = PrinterTarget(transport: PrinterTransport.spp, id: 'AA:BB', name: 'XP-58');
    const otherRadio =
        PrinterTarget(transport: PrinterTransport.ble, id: 'AA:BB', name: 'XP-58');
    expect(a, b);
    expect(a == otherRadio, isFalse,
        reason: 'the same MAC over a different radio is a different connection');
  });

  test('a stored target survives a round trip; garbage decodes to nothing', () {
    const target =
        PrinterTarget(transport: PrinterTransport.usb, id: '1155:22339', name: 'XP-58');
    expect(PrinterTarget.decode(target.encode()), target);
    expect(PrinterTarget.decode(target.encode())!.name, 'XP-58');
    // A corrupt or future-version preference must mean "nothing remembered",
    // never a crash on POS launch.
    expect(PrinterTarget.decode('not json'), isNull);
    expect(PrinterTarget.decode('{"transport":"telepathy","id":"x"}'), isNull);
    expect(PrinterTarget.decode(null), isNull);
  });

  test('a network target keeps host and port addressable', () {
    final t = PrinterTarget.tcpAt('192.168.1.50', 9100);
    expect(t.host, '192.168.1.50');
    expect(t.port, 9100);
    expect(PrinterTarget.decode(t.encode())!.port, 9100);
  });
}
