import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/auto_connect.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/core/printing/transports/spp_printer.dart';

/// CR-05/CR-06: a terminal's built-in printer (the reported Rovo internal link)
/// is already BONDED and never advertises, so it can never appear in a scan. The
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
      // CR-06 additions: the two models with no SDK and no integration. If they
      // present as a bonded SPP device at all, they must not read as a headset.
      'Sunrise-58',
      'CAPA Z91',
    ]) {
      expect(looksLikePrinterName(n), isTrue,
          reason: '"$n" should read as a printer');
    }
  });

  test('does not mistake everyday paired devices for printers', () {
    // These WILL be in the bonded list on a real terminal; connecting to one and
    // wondering why nothing prints is the failure this guards against.
    for (final n in ['AirPods Pro', 'Galaxy Buds', 'Car Kit', 'Ahmed iPhone', '']) {
      expect(looksLikePrinterName(n), isFalse,
          reason: '"$n" should NOT read as a printer');
    }
  });

  test('a device that DECLARES itself imaging counts even with a mute name', () {
    // Cheap ESC/POS units often report a meaningless name but a correct
    // Bluetooth class — and vice versa. Either signal is enough.
    const mute = SppDevice(address: 'AA:BB', name: 'BT-01', isPrinterClass: true);
    const named = SppDevice(address: 'CC:DD', name: 'XP-58');
    const neither = SppDevice(address: 'EE:FF', name: 'Galaxy Buds');
    expect(PrinterInventory.isLikelyPrinter(mute), isTrue);
    expect(PrinterInventory.isLikelyPrinter(named), isTrue);
    expect(PrinterInventory.isLikelyPrinter(neither), isFalse);
  });
}
