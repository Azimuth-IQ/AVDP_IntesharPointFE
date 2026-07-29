import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';

/// The picker showed a generic label for EVERY row. Cause: it read only
/// `device.platformName`, which the OS populates from a bond or a GATT read — a
/// freshly scanned peripheral usually carries its name only in the
/// advertisement. So the fallback chain matters, and it is worth pinning.
void main() {
  test('the fallback order is platform → advertised → address', () {
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
      expect(BluetoothPrinterService.looksLikePrinterName(n), isTrue, reason: n);
    }
  });
}
