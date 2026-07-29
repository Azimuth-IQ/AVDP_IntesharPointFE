import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';

/// CR-05: a terminal's built-in printer (the reported Rovo internal link) is
/// already BONDED and never advertises, so it can never appear in a scan. The
/// paired list surfaces it — but that list also contains headsets and phones,
/// so the printer-looking ones are marked and sorted first.
void main() {
  test('recognises the names real POS printers use', () {
    for (final n in [
      'RovoPrinter',
      'BLD-POS',
      'InnerPrinter',
      'BlueTooth Printer',
      'ESCPOS-58',
      'RP-330',
      'TM-T20',
      'POS-9200',
    ]) {
      expect(BluetoothPrinterService.looksLikePrinterName(n), isTrue,
          reason: '"$n" should read as a printer');
    }
  });

  test('does not mistake everyday paired devices for printers', () {
    // These WILL be in the bonded list on a real terminal; connecting to one and
    // wondering why nothing prints is the failure this guards against.
    for (final n in ['AirPods Pro', 'Galaxy Buds', 'Car Kit', 'Ahmed iPhone', '']) {
      expect(BluetoothPrinterService.looksLikePrinterName(n), isFalse,
          reason: '"$n" should NOT read as a printer');
    }
  });
}
