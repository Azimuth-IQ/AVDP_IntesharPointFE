import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/auto_connect.dart';
import 'package:inteshar/core/printing/printer_target.dart';

/// CR-06 auto-connect policy. The rule that matters commercially is the
/// ambiguous one: silently picking a printer and sending a paid voucher to the
/// wrong device is worse than asking the operator once.
void main() {
  const xprinter =
      PrinterTarget(transport: PrinterTransport.spp, id: 'AA:11', name: 'XP-58');
  const counterUnit =
      PrinterTarget(transport: PrinterTransport.spp, id: 'BB:22', name: 'POS-9200');
  const usbUnit =
      PrinterTarget(transport: PrinterTransport.usb, id: '1155:22339', name: 'XP-58');

  AutoConnectDecision decide({
    bool sunmi = false,
    bool intent = false,
    PrinterTarget? remembered,
    List<PrinterTarget> available = const [],
    List<PrinterTarget> candidates = const [],
  }) => decideAutoConnect(
    sunmiAvailable: sunmi,
    intentAvailable: intent,
    remembered: remembered,
    available: available,
    candidates: candidates,
  );

  group('the Sunmi inner printer always wins', () {
    test('even against a remembered device and other candidates', () {
      final d = decide(
        sunmi: true,
        intent: true,
        remembered: xprinter,
        available: const [xprinter, counterUnit],
        candidates: const [xprinter, counterUnit],
      );
      expect(d.action, AutoConnectAction.connect);
      expect(d.target, PrinterTarget.sunmiInner);
      expect(d.reason, AutoConnectReason.sunmiBuiltIn);
    });
  });

  group('ambiguity is asked about, never guessed', () {
    test('two plausible printers and nothing remembered → ask', () {
      final d = decide(
        available: const [xprinter, counterUnit],
        candidates: const [xprinter, counterUnit],
      );
      expect(d.action, AutoConnectAction.ask);
      expect(d.reason, AutoConnectReason.ambiguous);
      expect(d.candidates, [xprinter, counterUnit]);
      expect(d.target, isNull, reason: 'nothing may be adopted while ambiguous');
    });

    test('a Bluetooth and a USB printer together are still ambiguous', () {
      final d = decide(
        available: const [xprinter, usbUnit],
        candidates: const [xprinter, usbUnit],
      );
      expect(d.action, AutoConnectAction.ask);
    });

    test('the same printer listed twice is not ambiguity', () {
      final d = decide(
        available: const [xprinter],
        candidates: const [xprinter, xprinter],
      );
      expect(d.action, AutoConnectAction.connect);
      expect(d.target, xprinter);
      expect(d.reason, AutoConnectReason.soleCandidate);
    });

    test('several printers do NOT fall through to the lossy intent path', () {
      final d = decide(
        intent: true,
        available: const [xprinter, counterUnit],
        candidates: const [xprinter, counterUnit],
      );
      expect(d.action, AutoConnectAction.ask,
          reason: 'an approximate receipt is not a substitute for choosing');
    });
  });

  group('the remembered printer', () {
    test('beats an otherwise ambiguous set — it already printed here', () {
      final d = decide(
        remembered: counterUnit,
        available: const [xprinter, counterUnit],
        candidates: const [xprinter, counterUnit],
      );
      expect(d.action, AutoConnectAction.connect);
      expect(d.target, counterUnit);
      expect(d.reason, AutoConnectReason.remembered);
    });

    test('is skipped once it has been unpaired, leaving the rest to decide', () {
      final d = decide(
        remembered: counterUnit,
        available: const [xprinter],
        candidates: const [xprinter],
      );
      expect(d.target, xprinter);
      expect(d.reason, AutoConnectReason.soleCandidate);
    });

    test('unpaired AND two others left → ask, do not guess', () {
      const third =
          PrinterTarget(transport: PrinterTransport.spp, id: 'CC:33', name: 'RP-330');
      final d = decide(
        remembered: counterUnit,
        available: const [xprinter, third],
        candidates: const [xprinter, third],
      );
      expect(d.action, AutoConnectAction.ask);
    });

    test('a network printer is attempted even though nothing can enumerate it', () {
      final lan = PrinterTarget.tcpAt('192.168.1.50', 9100);
      final d = decide(remembered: lan);
      expect(d.action, AutoConnectAction.connect);
      expect(d.target, lan);
    });

    test('a BLE address is attempted without a scan — an exact MAC is never the '
        'wrong device', () {
      const le =
          PrinterTarget(transport: PrinterTransport.ble, id: 'DD:44', name: 'BLE-58');
      final d = decide(remembered: le);
      expect(d.action, AutoConnectAction.connect);
      expect(d.target, le);
    });

    test('a remembered vendor-intent printer is skipped when the app is gone', () {
      final d = decide(remembered: PrinterTarget.vendorIntent);
      expect(d.action, AutoConnectAction.none);
    });

    test('a remembered Sunmi on a non-Sunmi terminal is not attempted', () {
      final d = decide(remembered: PrinterTarget.sunmiInner);
      expect(d.action, AutoConnectAction.none,
          reason: 'the shop swapped hardware; do not pretend the head is there');
    });
  });

  group('the vendor intent path is genuinely last', () {
    test('used only when there is no real printer at all', () {
      final d = decide(intent: true);
      expect(d.action, AutoConnectAction.connect);
      expect(d.target, PrinterTarget.vendorIntent);
      expect(d.reason, AutoConnectReason.intentFallback);
      expect(d.isApproximate, isTrue,
          reason: 'the UI must be able to warn that this output differs');
    });

    test('loses to a single real printer on the same device', () {
      final d = decide(
        intent: true,
        available: const [xprinter],
        candidates: const [xprinter],
      );
      expect(d.target, xprinter);
      expect(d.isApproximate, isFalse);
    });
  });

  test('nothing anywhere is a quiet no-op, not an error', () {
    final d = decide();
    expect(d.action, AutoConnectAction.none);
    expect(d.reason, AutoConnectReason.nothingFound);
  });

  test('a paired headset is never a candidate, so it is never adopted', () {
    // The candidate list is built from the printer heuristic; this pins the
    // consequence: with only non-printers bonded, the POS asks nothing and
    // connects to nothing rather than printing a voucher to a headset.
    final d = decide(
      available: const [
        PrinterTarget(transport: PrinterTransport.spp, id: 'EE:55', name: 'AirPods Pro'),
      ],
    );
    expect(d.action, AutoConnectAction.none);
  });
}
